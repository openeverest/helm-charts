package main

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/openeverest/openeverest/v2/contract"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/yaml"
)

const ociScheme = "oci://"

// Metadata is the part of a chart's Chart.yaml that the check reads. Helm
// reads Chart.yaml with sigs.k8s.io/yaml, and writes it as JSON into the
// config blob of a chart it pushes to an OCI registry, so the JSON field names
// serve both.
type Metadata struct {
	Name         string            `json:"name"`
	Version      string            `json:"version"`
	Annotations  map[string]string `json:"annotations,omitempty"`
	Dependencies []Dependency      `json:"dependencies,omitempty"`
}

// Dependency is a chart dependency. In Chart.lock its Version is the exact
// version Helm resolved, not the range Chart.yaml asks for.
type Dependency struct {
	Name       string `json:"name"`
	Version    string `json:"version"`
	Repository string `json:"repository"`
}

type lock struct {
	Dependencies []Dependency `json:"dependencies"`
}

// Fetcher returns the Chart.yaml metadata of the chart at ref in an OCI
// registry, such as ghcr.io/openeverest/charts/plugin-hub:0.1.18.
type Fetcher interface {
	Fetch(ctx context.Context, ref string) (Metadata, error)
}

// check checks the dependencies locked in the Chart.lock of the core chart in
// chartDir against the compatibility window in its Chart.yaml. It reports
// every finding to r, and marks r failed when the chart must not be packaged.
func check(ctx context.Context, chartDir string, f Fetcher, r *reporter) {
	var chart Metadata
	if err := readYAML(filepath.Join(chartDir, "Chart.yaml"), &chart); err != nil {
		r.errorf("%v", err)
		return
	}
	core := describeCore(chart)

	window, ok := contract.WindowFromAnnotations(chart.Annotations)
	if !ok {
		r.noticef("%s carries no compatibility window (annotations %s and %s), so its bundled extensions cannot be checked; "+
			"make annotate-chart records the window once OpenEverest stamps it on its CRDs",
			core, contract.MinVersionAnnotation, contract.VersionAnnotation)
		return
	}
	if err := validateWindow(window); err != nil {
		r.errorf("%s carries an invalid compatibility window: %v", core, err)
		return
	}

	var locked lock
	err := readYAML(filepath.Join(chartDir, "Chart.lock"), &locked)
	switch {
	case errors.Is(err, fs.ErrNotExist) && len(chart.Dependencies) == 0:
		r.infof("%s has no dependencies", core)
		return
	case errors.Is(err, fs.ErrNotExist):
		r.errorf("%s has dependencies but no Chart.lock; run helm dependency update", core)
		return
	case err != nil:
		r.errorf("%v", err)
		return
	}

	for _, dep := range locked.Dependencies {
		checkDependency(ctx, dep, window, core, f, r)
	}
}

func checkDependency(ctx context.Context, dep Dependency, w contract.Window, core string, f Fetcher, r *reporter) {
	name := dep.Name + " " + dep.Version
	switch {
	case dep.Repository == "" || strings.HasPrefix(dep.Repository, "file://"):
		r.noticef("skipping %s: a local sub-chart is part of %s itself", name, core)
		return
	case !strings.HasPrefix(dep.Repository, ociScheme):
		r.noticef("skipping %s from %s: only dependencies from OCI registries are checked", name, dep.Repository)
		return
	}

	ref := ociReference(dep)
	md, err := f.Fetch(ctx, ref)
	if err != nil {
		r.errorf("cannot check %s: %v", name, err)
		return
	}
	if md.Name != dep.Name || md.Version != dep.Version {
		r.errorf("cannot check %s: %s holds %s %s", name, ref, md.Name, md.Version)
		return
	}

	stamp := md.Annotations[contract.VersionAnnotation]
	res := w.Check(stamp)
	msg := contract.Message(res, stamp, w)
	switch {
	case res.Status == metav1.ConditionTrue:
		r.infof("%s (built for OpenEverest %s) %s", name, stamp, msg)
	case res.Reason == contract.ReasonUnversioned:
		// Bundled extensions predate the declaration, so failing here would
		// block every release until they are rebuilt with it.
		r.warningf("%s %s. It is bundled anyway for now", name, msg)
	case res.Status == metav1.ConditionFalse:
		r.errorf("%s %s. %s accepts extensions built for OpenEverest %s to %s, so it must not bundle it",
			name, msg, upperFirst(core), w.Min, w.Current)
	default:
		r.errorf("%s %s. %s must not bundle an extension it cannot check", name, msg, upperFirst(core))
	}
}

// validateWindow rejects a window that no core would publish, which would
// make Check report InvalidVersion or CoreVersionSkew for every extension,
// even when the chart bundles none from a registry.
func validateWindow(w contract.Window) error {
	for _, v := range []struct{ key, value string }{
		{contract.MinVersionAnnotation, w.Min},
		{contract.VersionAnnotation, w.Current},
	} {
		if !contract.Valid(v.value) {
			return fmt.Errorf("%s %q is not a SemVer 2.0.0 version", v.key, v.value)
		}
	}
	if contract.Compare(w.Min, w.Current) > 0 {
		return fmt.Errorf("%s %s is above %s %s", contract.MinVersionAnnotation, w.Min, contract.VersionAnnotation, w.Current)
	}
	return nil
}

// ociReference returns the reference Helm pulls dep from. OCI tags cannot
// contain "+", so Helm pushes a version with build metadata under a tag with
// "_" in its place.
func ociReference(dep Dependency) string {
	repo := strings.TrimSuffix(strings.TrimPrefix(dep.Repository, ociScheme), "/")
	return fmt.Sprintf("%s/%s:%s", repo, dep.Name, strings.ReplaceAll(dep.Version, "+", "_"))
}

// describeCore names the core chart and the OpenEverest release it ships,
// which a release records next to the window.
func describeCore(chart Metadata) string {
	version := chart.Annotations[contract.CoreVersionKey]
	if version == "" {
		version = chart.Version
	}
	return fmt.Sprintf("the %s %s chart", chart.Name, version)
}

func upperFirst(s string) string {
	if s == "" {
		return s
	}
	return strings.ToUpper(s[:1]) + s[1:]
}

func readYAML(path string, v any) error {
	data, err := os.ReadFile(filepath.Clean(path))
	if err != nil {
		return fmt.Errorf("read %s: %w", path, err)
	}
	if err := yaml.Unmarshal(data, v); err != nil {
		return fmt.Errorf("parse %s: %w", path, err)
	}
	return nil
}
