// Command bundled-compat-check refuses a core chart that bundles an extension
// built for an OpenEverest the chart does not ship.
//
// The core chart bundles extensions as Helm dependencies: plugin-hub, for
// one, is installed by default. Such an extension reaches the cluster with
// the core chart itself, past every check that installers run on extensions,
// so the core chart must check it before it is packaged.
//
// The check reads the compatibility window that a release records in the
// core chart's Chart.yaml annotations, and the dependency versions locked in
// its Chart.lock. For every dependency from an OCI registry it reads the
// extension's Chart.yaml from the registry and checks the OpenEverest version
// the extension declares it was built for against the window. It fails when
// an extension is outside the window or its declaration cannot be checked,
// and only warns when an extension declares nothing, since bundled extensions
// predate the declaration. Local sub-charts are part of the core chart
// itself and are skipped, as are dependencies from HTTP chart repositories.
//
// Usage:
//
//	go run . -chart ../../charts/everest
package main

import (
	"context"
	"flag"
	"os"
	"time"
)

func main() {
	os.Exit(run())
}

func run() int {
	chartDir := flag.String("chart", ".", "directory of the core chart, holding its Chart.yaml and Chart.lock")
	timeout := flag.Duration("timeout", 2*time.Minute, "time allowed to read the metadata of every dependency")
	flag.Parse()

	ctx, cancel := context.WithTimeout(context.Background(), *timeout)
	defer cancel()

	r := newReporter(os.Stdout, os.Stderr, os.Getenv("GITHUB_ACTIONS") == "true")
	check(ctx, *chartDir, newOCIFetcher(), r)
	if r.failed {
		return 1
	}
	return 0
}
