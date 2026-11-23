package main

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// fakeFetcher serves chart metadata by reference and records what was
// fetched, so tests can tell skipped dependencies from checked ones.
type fakeFetcher struct {
	charts  map[string]Metadata
	errs    map[string]error
	fetched []string
}

func (f *fakeFetcher) Fetch(_ context.Context, ref string) (Metadata, error) {
	f.fetched = append(f.fetched, ref)
	if err, ok := f.errs[ref]; ok {
		return Metadata{}, err
	}
	md, ok := f.charts[ref]
	if !ok {
		return Metadata{}, errors.New("not found")
	}
	return md, nil
}

const pluginHubRef = "ghcr.io/openeverest/charts/plugin-hub:0.1.18"

// coreChart is a core Chart.yaml with the given annotations, as a release
// writes them, and the dependencies of the real chart.
func coreChart(annotations string) string {
	return `apiVersion: v2
name: openeverest
version: "2.1.0"
annotations:
  helm.sh/release-max-history: "5"
` + annotations + `dependencies:
  - name: common
    version: 0.0.*
    repository: "file://charts/common"
  - name: plugin-hub
    repository: "oci://ghcr.io/openeverest/charts"
    version: "0.1.*"
`
}

const window = `  openeverest.io/version: "2.1.0"
  openeverest.io/min-contract-version: "2.0.0"
  openeverest.io/contract-version: "2.1.0"
  openeverest.io/upgradable-from: "2.0.0"
`

const coreLockDependencies = `dependencies:
- name: common
  repository: file://charts/common
  version: 0.0.20
- name: pmm
  repository: https://percona.github.io/percona-helm-charts
  version: 1.3.21
- name: plugin-hub
  repository: oci://ghcr.io/openeverest/charts
  version: 0.1.18
`

const lockFooter = `digest: sha256:7553a62e9dbe55e2cccc1df2d3902e3b853a09b0f9eee669272e052d5ba75842
generated: "2026-11-19T21:20:17.034185762Z"
`

const coreLock = coreLockDependencies + lockFooter

func pluginHub(stamp string) map[string]Metadata {
	md := Metadata{Name: "plugin-hub", Version: "0.1.18"}
	if stamp != "" {
		md.Annotations = map[string]string{"openeverest.io/contract-version": stamp}
	}
	return map[string]Metadata{pluginHubRef: md}
}

func TestCheck(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name        string
		chart       string
		lock        string // no Chart.lock when empty
		charts      map[string]Metadata
		errs        map[string]error
		wantFailed  bool
		wantOutput  []string
		wantFetched []string
	}{
		{
			name:       "no window",
			chart:      coreChart(""),
			lock:       coreLock,
			wantOutput: []string{"notice: the openeverest 2.1.0 chart carries no compatibility window"},
		},
		{
			name:        "extension inside the window",
			chart:       coreChart(window),
			lock:        coreLock,
			charts:      pluginHub("2.0.1"),
			wantOutput:  []string{"plugin-hub 0.1.18 (built for OpenEverest 2.0.1) works with this version of OpenEverest"},
			wantFetched: []string{pluginHubRef},
		},
		{
			name:        "extension at the minimum",
			chart:       coreChart(window),
			lock:        coreLock,
			charts:      pluginHub("2.0.0"),
			wantOutput:  []string{"plugin-hub 0.1.18 (built for OpenEverest 2.0.0) works"},
			wantFetched: []string{pluginHubRef},
		},
		{
			name:        "extension at the current version",
			chart:       coreChart(window),
			lock:        coreLock,
			charts:      pluginHub("2.1.0"),
			wantOutput:  []string{"plugin-hub 0.1.18 (built for OpenEverest 2.1.0) works"},
			wantFetched: []string{pluginHubRef},
		},
		{
			name:       "extension built for a newer core",
			chart:      coreChart(window),
			lock:       coreLock,
			charts:     pluginHub("2.2.0"),
			wantFailed: true,
			wantOutput: []string{
				"error: plugin-hub 0.1.18 needs OpenEverest 2.2.0 or later. " +
					"The openeverest 2.1.0 chart accepts extensions built for OpenEverest 2.0.0 to 2.1.0, so it must not bundle it",
			},
			wantFetched: []string{pluginHubRef},
		},
		{
			name:       "extension built for an unreleased core",
			chart:      coreChart(window),
			lock:       coreLock,
			charts:     pluginHub("2.1.1-dev"),
			wantFailed: true,
			wantOutput: []string{
				"error: plugin-hub 0.1.18 needs a newer, unreleased OpenEverest build",
			},
			wantFetched: []string{pluginHubRef},
		},
		{
			name:       "extension built for a core below the minimum",
			chart:      coreChart(window),
			lock:       coreLock,
			charts:     pluginHub("2.0.0-alpha.1"),
			wantFailed: true,
			wantOutput: []string{
				"error: plugin-hub 0.1.18 was built for an older OpenEverest; update it to a release built for OpenEverest 2.0.0 or later. " +
					"The openeverest 2.1.0 chart accepts extensions built for OpenEverest 2.0.0 to 2.1.0, so it must not bundle it",
			},
			wantFetched: []string{pluginHubRef},
		},
		{
			name:   "unstamped extension",
			chart:  coreChart(window),
			lock:   coreLock,
			charts: pluginHub(""),
			wantOutput: []string{
				"warning: plugin-hub 0.1.18 does not declare the OpenEverest it was built for, so its compatibility cannot be checked. It is bundled anyway for now",
			},
			wantFetched: []string{pluginHubRef},
		},
		{
			name:       "invalid stamp",
			chart:      coreChart(window),
			lock:       coreLock,
			charts:     pluginHub("v2.1.0"),
			wantFailed: true,
			wantOutput: []string{
				`error: plugin-hub 0.1.18 declares an invalid OpenEverest version "v2.1.0", so its compatibility cannot be checked. ` +
					"The openeverest 2.1.0 chart must not bundle an extension it cannot check",
			},
			wantFetched: []string{pluginHubRef},
		},
		{
			name:        "local and HTTP dependencies are skipped",
			chart:       coreChart(window),
			lock:        coreLock,
			charts:      pluginHub("2.1.0"),
			wantOutput:  []string{"notice: skipping common 0.0.20: a local sub-chart is part of the openeverest 2.1.0 chart itself", "notice: skipping pmm 1.3.21 from https://percona.github.io/percona-helm-charts: only dependencies from OCI registries are checked"},
			wantFetched: []string{pluginHubRef},
		},
		{
			name:  "every dependency is checked",
			chart: coreChart(window),
			lock: coreLockDependencies + `- name: other
  repository: oci://registry.example.com/charts/
  version: 1.0.0+build.1
` + lockFooter,
			charts: map[string]Metadata{
				"registry.example.com/charts/other:1.0.0_build.1": {
					Name: "other", Version: "1.0.0+build.1",
					Annotations: map[string]string{"openeverest.io/contract-version": "2.2.0"},
				},
				pluginHubRef: pluginHub("2.1.0")[pluginHubRef],
			},
			wantFailed:  true,
			wantOutput:  []string{"plugin-hub 0.1.18 (built for OpenEverest 2.1.0) works", "error: other 1.0.0+build.1 needs OpenEverest 2.2.0 or later"},
			wantFetched: []string{pluginHubRef, "registry.example.com/charts/other:1.0.0_build.1"},
		},
		{
			name:        "registry error",
			chart:       coreChart(window),
			lock:        coreLock,
			errs:        map[string]error{pluginHubRef: errors.New("unauthorized")},
			wantFailed:  true,
			wantOutput:  []string{"error: cannot check plugin-hub 0.1.18: unauthorized"},
			wantFetched: []string{pluginHubRef},
		},
		{
			name:  "registry holds another chart",
			chart: coreChart(window),
			lock:  coreLock,
			charts: map[string]Metadata{
				pluginHubRef: {Name: "plugin-hub", Version: "0.1.19"},
			},
			wantFailed:  true,
			wantOutput:  []string{"error: cannot check plugin-hub 0.1.18: " + pluginHubRef + " holds plugin-hub 0.1.19"},
			wantFetched: []string{pluginHubRef},
		},
		{
			name: "minimum above the current version",
			chart: coreChart(`  openeverest.io/min-contract-version: "2.2.0"
  openeverest.io/contract-version: "2.1.0"
`),
			lock:       coreLock,
			wantFailed: true,
			wantOutput: []string{"error: the openeverest 2.1.0 chart carries an invalid compatibility window: openeverest.io/min-contract-version 2.2.0 is above openeverest.io/contract-version 2.1.0"},
		},
		{
			name: "partial window",
			chart: coreChart(`  openeverest.io/contract-version: "2.1.0"
`),
			lock:       coreLock,
			wantFailed: true,
			wantOutput: []string{`error: the openeverest 2.1.0 chart carries an invalid compatibility window: openeverest.io/min-contract-version "" is not a SemVer 2.0.0 version`},
		},
		{
			name: "invalid current version",
			chart: coreChart(`  openeverest.io/min-contract-version: "2.0.0"
  openeverest.io/contract-version: "2.1"
`),
			lock:       coreLock,
			wantFailed: true,
			wantOutput: []string{`openeverest.io/contract-version "2.1" is not a SemVer 2.0.0 version`},
		},
		{
			name:       "dependencies without Chart.lock",
			chart:      coreChart(window),
			wantFailed: true,
			wantOutput: []string{"error: the openeverest 2.1.0 chart has dependencies but no Chart.lock; run helm dependency update"},
		},
		{
			name: "no dependencies",
			chart: `apiVersion: v2
name: openeverest
version: 2.1.0
annotations:
` + window,
			wantOutput: []string{"the openeverest 2.1.0 chart has no dependencies"},
		},
		{
			name:       "invalid Chart.lock",
			chart:      coreChart(window),
			lock:       "dependencies: {",
			wantFailed: true,
			wantOutput: []string{"error: parse ", "Chart.lock"},
		},
		{
			name: "no openeverest.io/version annotation",
			chart: coreChart(`  openeverest.io/min-contract-version: "2.0.0"
  openeverest.io/contract-version: "2.0.0"
`),
			lock:        coreLock,
			charts:      pluginHub("2.1.0"),
			wantFailed:  true,
			wantOutput:  []string{"The openeverest 2.1.0 chart accepts extensions built for OpenEverest 2.0.0 to 2.0.0"},
			wantFetched: []string{pluginHubRef},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			dir := t.TempDir()
			require.NoError(t, os.WriteFile(filepath.Join(dir, "Chart.yaml"), []byte(tt.chart), 0o600))
			if tt.lock != "" {
				require.NoError(t, os.WriteFile(filepath.Join(dir, "Chart.lock"), []byte(tt.lock), 0o600))
			}
			f := &fakeFetcher{charts: tt.charts, errs: tt.errs}
			var out bytes.Buffer
			r := newReporter(&out, &out, false)

			check(t.Context(), dir, f, r)

			assert.Equal(t, tt.wantFailed, r.failed, out.String())
			for _, want := range tt.wantOutput {
				assert.Contains(t, out.String(), want)
			}
			assert.Equal(t, tt.wantFetched, f.fetched)
		})
	}
}

func TestCheckMissingChart(t *testing.T) {
	t.Parallel()

	var out bytes.Buffer
	r := newReporter(&out, &out, false)

	check(t.Context(), t.TempDir(), &fakeFetcher{}, r)

	assert.True(t, r.failed)
	assert.Contains(t, out.String(), "error: read ")
}

func TestOCIReference(t *testing.T) {
	t.Parallel()

	tests := []struct {
		dep  Dependency
		want string
	}{
		{
			dep:  Dependency{Name: "plugin-hub", Version: "0.1.18", Repository: "oci://ghcr.io/openeverest/charts"},
			want: "ghcr.io/openeverest/charts/plugin-hub:0.1.18",
		},
		{
			dep:  Dependency{Name: "plugin-hub", Version: "0.1.18", Repository: "oci://ghcr.io/openeverest/charts/"},
			want: "ghcr.io/openeverest/charts/plugin-hub:0.1.18",
		},
		{
			dep:  Dependency{Name: "x", Version: "1.0.0-rc.1+build.5", Repository: "oci://localhost:5000"},
			want: "localhost:5000/x:1.0.0-rc.1_build.5",
		},
	}
	for _, tt := range tests {
		t.Run(tt.want, func(t *testing.T) {
			t.Parallel()
			assert.Equal(t, tt.want, ociReference(tt.dep))
		})
	}
}

func TestReporterGitHub(t *testing.T) {
	t.Parallel()

	var out, errOut bytes.Buffer
	r := newReporter(&out, &errOut, true)

	r.infof("plain")
	r.noticef("a notice")
	r.warningf("100%% sure\nnot")
	r.errorf("an error")

	assert.True(t, r.failed)
	assert.Equal(t, "plain\n::notice::a notice\n::warning::100%25 sure%0Anot\n::error::an error\n", out.String())
	assert.Empty(t, errOut.String())
}

func TestReporterLocal(t *testing.T) {
	t.Parallel()

	var out, errOut bytes.Buffer
	r := newReporter(&out, &errOut, false)

	r.infof("plain")
	r.noticef("a notice")
	r.warningf("a warning")

	assert.False(t, r.failed)
	assert.Equal(t, "plain\nnotice: a notice\n", out.String())
	assert.Equal(t, "warning: a warning\n", errOut.String())
}
