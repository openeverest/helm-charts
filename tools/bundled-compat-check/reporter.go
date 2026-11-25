package main

import (
	"fmt"
	"io"
	"strings"
)

// reporter prints the findings of the check, as workflow commands when it
// runs in GitHub Actions so that they show up as annotations on the run.
type reporter struct {
	out    io.Writer
	errOut io.Writer
	github bool
	failed bool
}

func newReporter(out, errOut io.Writer, github bool) *reporter {
	return &reporter{out: out, errOut: errOut, github: github}
}

func (r *reporter) infof(format string, args ...any) {
	_, _ = fmt.Fprintf(r.out, format+"\n", args...)
}

func (r *reporter) noticef(format string, args ...any) {
	r.printf(r.out, "notice", format, args...)
}

func (r *reporter) warningf(format string, args ...any) {
	r.printf(r.errOut, "warning", format, args...)
}

// errorf reports a finding that must stop the chart from being packaged.
func (r *reporter) errorf(format string, args ...any) {
	r.failed = true
	r.printf(r.errOut, "error", format, args...)
}

func (r *reporter) printf(w io.Writer, level, format string, args ...any) {
	msg := fmt.Sprintf(format, args...)
	if r.github {
		// One stream keeps the annotations in the order they were found.
		_, _ = fmt.Fprintf(r.out, "::%s::%s\n", level, escapeWorkflowData(msg))
		return
	}
	_, _ = fmt.Fprintf(w, "%s: %s\n", level, msg)
}

// escapeWorkflowData keeps a message one workflow command long.
func escapeWorkflowData(s string) string {
	return strings.NewReplacer("%", "%25", "\r", "%0D", "\n", "%0A").Replace(s)
}
