// Regenerates ../generated: the victoria-metrics-k8s-stack chart's default
// rules and dashboards.
//
// The chart (>= 0.85) only ships these via a sync job that downloads them from
// unpinned upstream branches and applies them imperatively on every install
// and upgrade. Instead, this builds the sync job from the same chart release,
// runs it in output mode against the HelmRelease's values, and vendors the
// result for Flux to apply. Upstream changes show up as diffs in the chart
// bump PR. Renovate runs this on chart bumps (see .renovaterc.json5).
//
// This can be removed in favor of a chart if
// https://github.com/VictoriaMetrics/helm-charts/issues/3040#issuecomment-6076709839
// is implemented.
//
// Run from this directory (go -C <this dir> run .). Requires git, go and helm.
package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"go.yaml.in/yaml/v3"
)

const (
	release   = "victoria-metrics-k8s-stack"
	namespace = "monitoring"
	chartRef  = "oci://ghcr.io/victoriametrics/helm-charts/victoria-metrics-k8s-stack"
	chartRepo = "https://github.com/VictoriaMetrics/helm-charts"
)

// Sync job log lines that don't indicate a skipped source or object.
var expectedLog = regexp.MustCompile(` (applied (vmrule|dashboard) |skipping disabled rule group |warning: resource name .* truncated)`)

func main() {
	log.SetFlags(0)
	hrPath := flag.String("hr", "../../k8s-stack/hr.yaml", "HelmRelease to read the chart version and values from")
	outDir := flag.String("out", "../generated", "output directory, replaced entirely")
	flag.Parse()

	if err := run(*hrPath, *outDir); err != nil {
		log.Fatalf("error: %v", err)
	}
}

func run(hrPath, outDir string) error {
	work, err := os.MkdirTemp("", "sync-job-")
	if err != nil {
		return fmt.Errorf("create work directory: %w", err)
	}
	defer os.RemoveAll(work)

	version, values, err := readHelmRelease(hrPath)
	if err != nil {
		return fmt.Errorf("read HelmRelease %s: %w", hrPath, err)
	}

	valuesPath := filepath.Join(work, "values.yaml")
	if err := os.WriteFile(valuesPath, values, 0o644); err != nil {
		return fmt.Errorf("write chart values: %w", err)
	}

	syncJob, err := buildSyncJob(work, version)
	if err != nil {
		return fmt.Errorf("build sync job for chart %s: %w", version, err)
	}

	configPath, err := renderConfig(work, version, valuesPath)
	if err != nil {
		return fmt.Errorf("render sync job config for chart %s: %w", version, err)
	}

	outputPath := filepath.Join(work, "output.yaml")
	if err := runSyncJob(syncJob, configPath, outputPath); err != nil {
		return fmt.Errorf("run sync job: %w", err)
	}

	// Write next to the destination, then swap, so a failure leaves the
	// existing output untouched.
	staging, err := os.MkdirTemp(filepath.Dir(filepath.Clean(outDir)), ".generated-")
	if err != nil {
		return fmt.Errorf("create staging directory next to %s: %w", outDir, err)
	}
	defer os.RemoveAll(staging)

	if err := split(outputPath, staging, outDir); err != nil {
		return fmt.Errorf("split sync job output: %w", err)
	}

	if err := os.RemoveAll(outDir); err != nil {
		return fmt.Errorf("remove previous output %s: %w", outDir, err)
	}

	if err := os.Chmod(staging, 0o755); err != nil {
		return fmt.Errorf("set staging directory permissions: %w", err)
	}

	if err := os.Rename(staging, outDir); err != nil {
		return fmt.Errorf("move staging directory to %s: %w", outDir, err)
	}

	return nil
}

// readHelmRelease returns the chart version and spec.values.
func readHelmRelease(path string) (string, []byte, error) {
	var hr struct {
		Spec struct {
			Chart struct {
				Spec struct {
					Version string `yaml:"version"`
				} `yaml:"spec"`
			} `yaml:"chart"`
			Values map[string]any `yaml:"values"`
		} `yaml:"spec"`
	}

	b, err := os.ReadFile(path)
	if err != nil {
		return "", nil, fmt.Errorf("read file: %w", err)
	}

	if err := yaml.Unmarshal(b, &hr); err != nil {
		return "", nil, fmt.Errorf("parse YAML: %w", err)
	}

	version := hr.Spec.Chart.Spec.Version
	if version == "" {
		return "", nil, errors.New("no spec.chart.spec.version")
	}

	values, err := yaml.Marshal(hr.Spec.Values)
	if err != nil {
		return "", nil, fmt.Errorf("marshal spec.values: %w", err)
	}

	return version, values, nil
}

// buildSyncJob builds the sync job from the chart release's tag. Its module
// path doesn't match its location in the repo, so it can't be fetched as a
// Go module.
func buildSyncJob(work, version string) (string, error) {
	src := filepath.Join(work, "helm-charts")
	tag := "victoria-metrics-k8s-stack-" + version
	err := command("",
		"git", "-c", "advice.detachedHead=false", "clone", "--quiet", "--depth=1",
		"--filter=blob:none", "--sparse", "--branch="+tag,
		chartRepo, src,
	).Run()
	if err != nil {
		return "", fmt.Errorf("clone %s at %s: %w", chartRepo, tag, err)
	}

	if err := command(src, "git", "sparse-checkout", "set", "hack/sync-job").Run(); err != nil {
		return "", fmt.Errorf("check out hack/sync-job: %w", err)
	}

	bin := filepath.Join(work, "sync-job")
	build := command(filepath.Join(src, "hack", "sync-job"), "go", "build", "-o", bin, ".")
	// Same flags as upstream's Dockerfile. -p=2: unbounded parallel compiles
	// peak at ~1.4 GB, which doesn't fit next to Renovate in its job pod.
	build.Env = append(os.Environ(), "GOEXPERIMENT=jsonv2", "CGO_ENABLED=0", "GOFLAGS=-p=2")
	if err := build.Run(); err != nil {
		return "", fmt.Errorf("go build: %w", err)
	}
	return bin, nil
}

// renderConfig renders the sync job's config from the chart. The HelmRelease
// disables the job itself, which also skips its config.
func renderConfig(work, version, valuesPath string) (string, error) {
	cmd := command("", "helm", "template", release, chartRef,
		"--version", version,
		"--namespace", namespace,
		"--values", valuesPath,
		"--set", "syncJob.enabled=true",
		"--show-only", "templates/sync-job/config.yaml",
	)
	var rendered bytes.Buffer
	cmd.Stdout = &rendered
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("helm template: %w", err)
	}

	var cm struct {
		Data map[string]string `yaml:"data"`
	}
	if err := yaml.Unmarshal(rendered.Bytes(), &cm); err != nil {
		return "", fmt.Errorf("parse rendered ConfigMap: %w", err)
	}
	config, ok := cm.Data["config.yaml"]
	if !ok {
		return "", errors.New("rendered ConfigMap has no data.config.yaml")
	}
	path := filepath.Join(work, "config.yaml")
	if err := os.WriteFile(path, []byte(config), 0o644); err != nil {
		return "", fmt.Errorf("write config: %w", err)
	}
	return path, nil
}

// runSyncJob fails on any unexpected log line: the job only logs parse and
// render errors, and skips the affected source or object, which would
// silently drop it from the output.
func runSyncJob(bin, configPath, outputPath string) error {
	cmd := command("", bin)
	// Upstream code, run with only what it needs. Renovate's environment holds
	// the GitHub App token, which is valid for every installed repository.
	// This doesn't stop a same-user process from reading /proc/<ppid>/environ.
	cmd.Env = []string{
		"CONFIG=" + configPath,
		"OUTPUT=" + outputPath,
		"RELEASE=" + release,
		"NAMESPACE=" + namespace,
	}
	for _, key := range []string{"HOME", "PATH", "TMPDIR", "SSL_CERT_FILE", "SSL_CERT_DIR", "HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY"} {
		if value, ok := os.LookupEnv(key); ok {
			cmd.Env = append(cmd.Env, key+"="+value)
		}
	}
	var logs bytes.Buffer
	cmd.Stderr = &logs
	runErr := cmd.Run()

	var unexpected []string
	scanner := bufio.NewScanner(&logs)
	for scanner.Scan() {
		if line := scanner.Text(); !expectedLog.MatchString(line) {
			unexpected = append(unexpected, line)
		}
	}
	if err := scanner.Err(); err != nil {
		return fmt.Errorf("read sync job logs: %w", err)
	}
	if runErr != nil {
		return fmt.Errorf("sync job failed: %w\n%s", runErr, strings.Join(unexpected, "\n"))
	}
	if len(unexpected) > 0 {
		return fmt.Errorf("sync job logged errors (sources or objects were skipped):\n%s", strings.Join(unexpected, "\n"))
	}
	return nil
}

// split writes one file per object, with dashboard JSON indented, plus a
// kustomization.yaml, into dir. outDir is where dir will end up.
func split(path, dir, outDir string) error {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()

	var files []string
	dec := yaml.NewDecoder(f)
	for {
		var doc yaml.Node
		if err := dec.Decode(&doc); err != nil {
			if errors.Is(err, io.EOF) {
				break
			}

			return fmt.Errorf("parse %s: %w", path, err)
		}

		if len(doc.Content) == 0 {
			continue
		}

		obj := doc.Content[0]

		kind := scalar(obj, "kind")
		name := scalar(lookup(obj, "metadata"), "name")

		var subdir string
		switch kind {
		case "VMRule":
			subdir = "rules"
		case "GrafanaDashboard":
			subdir = "dashboards"
			if err := indentDashboard(obj); err != nil {
				return fmt.Errorf("indent GrafanaDashboard %s: %w", name, err)
			}
		default:
			return fmt.Errorf("unexpected object kind %q (%s)", kind, name)
		}

		if name == "" || strings.ContainsAny(name, "/\n") {
			return fmt.Errorf("unexpected %s name %q", kind, name)
		}

		file := filepath.Join(subdir, name+".yaml")
		h, err := header(outDir, file)
		if err != nil {
			return fmt.Errorf("build header for %s: %w", file, err)
		}

		if err := writeYAML(filepath.Join(dir, file), h, obj); err != nil {
			return fmt.Errorf("write %s %s: %w", kind, name, err)
		}

		files = append(files, file)
	}

	if len(files) == 0 {
		return fmt.Errorf("no objects in %s", path)
	}

	sort.Strings(files)

	h, err := header(outDir, "kustomization.yaml")
	if err != nil {
		return fmt.Errorf("build header for kustomization.yaml: %w", err)
	}

	var k bytes.Buffer
	k.WriteString(h)
	k.WriteString("---\napiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\n")
	k.WriteString("# Dashboards use Grafana's ${variable} syntax.\n")
	k.WriteString("commonAnnotations:\n  kustomize.toolkit.fluxcd.io/substitute: disabled\n")
	k.WriteString("resources:\n")

	for _, file := range files {
		fmt.Fprintf(&k, "  - ./%s\n", file)
	}

	if err := os.WriteFile(filepath.Join(dir, "kustomization.yaml"), k.Bytes(), 0o644); err != nil {
		return fmt.Errorf("write kustomization.yaml: %w", err)
	}

	return nil
}

// indentDashboard rewrites spec.json as indented JSON in a literal block so
// that upstream changes are reviewable line by line.
func indentDashboard(obj *yaml.Node) error {
	j := lookup(lookup(obj, "spec"), "json")
	if j == nil {
		return errors.New("no spec.json")
	}

	var out bytes.Buffer
	if err := json.Indent(&out, []byte(j.Value), "", "  "); err != nil {
		return fmt.Errorf("indent spec.json: %w", err)
	}

	j.Value = out.String() + "\n"
	j.Style = yaml.LiteralStyle

	return nil
}

// header points from the output file back at this tool (the current
// directory).
func header(outDir, file string) (string, error) {
	toolDir, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("get current directory: %w", err)
	}

	fileDir, err := filepath.Abs(filepath.Join(outDir, filepath.Dir(file)))
	if err != nil {
		return "", fmt.Errorf("resolve output directory: %w", err)
	}

	rel, err := filepath.Rel(fileDir, toolDir)
	if err != nil {
		return "", fmt.Errorf("relative path from %s to %s: %w", fileDir, toolDir, err)
	}

	return "# DO NOT EDIT - generated by " + filepath.ToSlash(rel) + "\n", nil
}

func writeYAML(path, header string, obj *yaml.Node) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("create directory: %w", err)
	}

	var b bytes.Buffer
	b.WriteString(header)
	b.WriteString("---\n")
	enc := yaml.NewEncoder(&b)
	enc.SetIndent(2)
	if err := enc.Encode(obj); err != nil {
		return fmt.Errorf("encode YAML: %w", err)
	}

	if err := enc.Close(); err != nil {
		return fmt.Errorf("flush YAML encoder: %w", err)
	}

	if err := os.WriteFile(path, b.Bytes(), 0o644); err != nil {
		return fmt.Errorf("write file: %w", err)
	}

	return nil
}

func lookup(n *yaml.Node, key string) *yaml.Node {
	if n == nil || n.Kind != yaml.MappingNode {
		return nil
	}

	for i := 0; i+1 < len(n.Content); i += 2 {
		if n.Content[i].Value == key {
			return n.Content[i+1]
		}
	}

	return nil
}

func scalar(n *yaml.Node, key string) string {
	if v := lookup(n, key); v != nil && v.Kind == yaml.ScalarNode {
		return v.Value
	}

	return ""
}

// command runs name in dir (the current directory if empty), passing its
// output through to stderr.
func command(dir, name string, args ...string) *exec.Cmd {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr
	return cmd
}
