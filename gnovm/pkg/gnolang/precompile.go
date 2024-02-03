package gnolang

import (
	"bytes"
	"errors"
	"fmt"
	"go/ast"
	"go/format"
	"go/parser"
	"go/token"
	"io"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"go.uber.org/multierr"
	"golang.org/x/tools/go/ast/astutil"

	"github.com/gnolang/gno/tm2/pkg/std"
)

const (
	GnoRealmPkgsPrefixBefore = "gno.land/r/"
	GnoRealmPkgsPrefixAfter  = "github.com/gnolang/gno/examples/gno.land/r/"
	GnoPackagePrefixBefore   = "gno.land/p/demo/"
	GnoPackagePrefixAfter    = "github.com/gnolang/gno/examples/gno.land/p/demo/"
	GnoStdPkgBefore          = "std"
	GnoStdPkgAfter           = "github.com/gnolang/gno/gnovm/stdlibs/stdshim"
)

var stdlibWhitelist = []string{
	// go
	"bufio",
	"bytes",
	"compress/gzip",
	"context",
	"crypto/md5",
	"crypto/sha1",
	"crypto/sha256",
	"encoding/base64",
	"encoding/binary",
	"encoding/hex",
	"encoding/json",
	"encoding/xml",
	"errors",
	"flag",
	"fmt",
	"io",
	"io/util",
	"math",
	"math/big",
	"math/rand",
	"regexp",
	"sort",
	"strconv",
	"strings",
	"text/template",
	"time",
	"unicode/utf8",

	// gno
	"std",
}

var importPrefixWhitelist = []string{
	"github.com/gnolang/gno/_test",
}

const ImportPrefix = "github.com/gnolang/gno"

type precompileResult struct {
	Imports    []*ast.ImportSpec
	Translated string
}

// TODO: func PrecompileFile: supports caching.
// TODO: func PrecompilePkg: supports directories.

func guessRootDir(fileOrPkg string, goBinary string) (string, error) {
	abs, err := filepath.Abs(fileOrPkg)
	if err != nil {
		return "", err
	}
	args := []string{"list", "-m", "-mod=mod", "-f", "{{.Dir}}", ImportPrefix}
	cmd := exec.Command(goBinary, args...)
	cmd.Dir = abs
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("can't guess --root-dir")
	}
	rootDir := strings.TrimSpace(string(out))
	return rootDir, nil
}

// GetPrecompileFilenameAndTags returns the filename and tags for precompiled files.
func GetPrecompileFilenameAndTags(gnoFilePath string, isPureGo bool) (targetFilename, tags string) {
	nameNoExtension := strings.TrimSuffix(filepath.Base(gnoFilePath), ".gno")
	switch {
	case strings.HasSuffix(gnoFilePath, "_filetest.gno"):
		tags = "gno && filetest"
		if isPureGo {
			targetFilename = "." + nameNoExtension + ".go"
		} else {
			targetFilename = "." + nameNoExtension + ".gno.gen.go"
		}
	case strings.HasSuffix(gnoFilePath, "_test.gno"):
		tags = "gno && test"
		if isPureGo {
			targetFilename = "." + nameNoExtension + ".go"
		} else {
			targetFilename = "." + nameNoExtension + ".gno.gen_test.go"
		}
	default:
		tags = "gno"
		if isPureGo {
			targetFilename = nameNoExtension + ".go"
		} else {
			targetFilename = nameNoExtension + ".gno.gen.go"
		}
	}
	return
}

func PrecompileAndCheckMempkg(mempkg *std.MemPackage) error {
	gofmt := "gofmt"

	tmpDir, err := os.MkdirTemp("", mempkg.Name)
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmpDir) //nolint: errcheck

	var errs error
	for _, mfile := range mempkg.Files {
		if !strings.HasSuffix(mfile.Name, ".gno") {
			continue // skip spurious file.
		}
		res, err := Precompile(mfile.Body, "gno,tmp", mfile.Name)
		if err != nil {
			errs = multierr.Append(errs, err)
			continue
		}
		tmpFile := filepath.Join(tmpDir, mfile.Name)
		err = os.WriteFile(tmpFile, []byte(res.Translated), 0o644)
		if err != nil {
			errs = multierr.Append(errs, err)
			continue
		}
		err = PrecompileVerifyFile(tmpFile, gofmt)
		if err != nil {
			errs = multierr.Append(errs, err)
			continue
		}
	}
	if errs != nil {
		return fmt.Errorf("precompile package: %w", errs)
	}
	return nil
}

func PrecompileAndRunMempkg(mempkg *std.MemPackage, path string) (error, string) {
	goRun := "go run"

	tmpDir, err := os.MkdirTemp("", mempkg.Name)
	if err != nil {
		return err, ""
	}
	defer os.RemoveAll(tmpDir) //nolint: errcheck

	var errs error
	var output string
	for _, mfile := range mempkg.Files {
		if !strings.HasSuffix(mfile.Name, ".gno") {
			continue // skip spurious file.
		}
		res, err := Precompile(mfile.Body, "no_header", mfile.Name)
		if err != nil {
			errs = multierr.Append(errs, err)
			continue
		}
		//tmpFile := filepath.Join(tmpDir, mfile.Name)
		targetFileName, _ := GetPrecompileFilenameAndTags(mfile.Name, true)
		fmt.Println("---targetFileName:", targetFileName)
		err = os.WriteFile(filepath.Join(tmpDir, targetFileName), []byte(res.Translated), 0o644)
		if err != nil {
			errs = multierr.Append(errs, err)
			continue
		}
		// check precompiled file
		err, output = PrecompileRun(targetFileName, tmpDir, goRun, path)
		if err != nil {
			errs = multierr.Append(errs, err)
			continue
		}
	}
	if errs != nil {
		//return fmt.Errorf("precompile package: %w", errs), ""
		return errs, ""
	}
	fmt.Println("---output before return is:", output)
	return nil, output
}

func Precompile(source string, tags string, filename string) (*precompileResult, error) {
	fmt.Println("---Precompile, filename: ", filename)
	var out bytes.Buffer

	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, filename, source, parser.ParseComments)
	if err != nil {
		return nil, fmt.Errorf("parse: %w", err)
	}

	isTestFile := strings.HasSuffix(filename, "_test.gno") || strings.HasSuffix(filename, "_filetest.gno")
	shouldCheckWhitelist := !isTestFile

	transformed, err := precompileAST(fset, f, shouldCheckWhitelist)
	if err != nil {
		return nil, fmt.Errorf("%w", err)
	}

	var header string
	if tags != "no_header" {
		header = "// Code generated by github.com/gnolang/gno. DO NOT EDIT.\n\n"
		if tags != "" {
			header += "//go:build " + tags + "\n\n"
		}
		_, err = out.WriteString(header)
		if err != nil {
			return nil, fmt.Errorf("write to buffer: %w", err)
		}
	}
	err = format.Node(&out, fset, transformed)

	res := &precompileResult{
		Imports:    f.Imports,
		Translated: out.String(),
	}
	return res, nil
}

// PrecompileVerifyFile tries to run `go fmt` against a precompiled .go file.
//
// This is fast and won't look the imports.
// TODO: add go vet here
func PrecompileVerifyFile(path string, gofmtBinary string) error {
	// TODO: use cmd/parser instead of exec?

	args := strings.Split(gofmtBinary, " ")
	args = append(args, []string{"-l", "-e", path}...)
	cmd := exec.Command(args[0], args[1:]...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Fprintln(os.Stderr, string(out))
		return fmt.Errorf("%s: %w", gofmtBinary, err)
	}
	return nil
}

func PrecompileRun(fileName string, tmpDir string, goRunBinary string, path string) (error, string) {
	fmt.Printf("---PrecompileRun, dir: %s, gorun: %s \n", tmpDir, goRunBinary)
	// TODO: use cmd/parser instead of exec?

	originalDir, err := os.Getwd()
	if err != nil {
		fmt.Println("Error getting current working directory:", err)
		return err, ""
	}

	defer func() {
		err = os.Chdir(originalDir) // switch dir back
		if err != nil {
			fmt.Println("Error changing back to original directory:", err)
			panic(err)
		}
	}()

	if debug {
		// Read the directory contents
		files, err := ioutil.ReadDir(tmpDir)
		if err != nil {
			fmt.Println("Error reading directory:", err)
			return err, ""
		}
		// Iterate over the files and print their names
		for _, file := range files {
			fmt.Println("---file: ", file.Name())
		}
		content, err := os.ReadFile("main.go")
		if err != nil {
			fmt.Println("Error reading file contents:", err)
			return err, ""
		}

		fmt.Println("File contents:")
		fmt.Println(string(content))
	}

	args := strings.Split(goRunBinary, " ")
	args = append(args, filepath.Join(tmpDir, fileName))
	//args = append(args, fileName)
	fmt.Println("---args: ", args)

	cmd := exec.Command(args[0], args[1:]...)

	// Create pipes to capture stdout and stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		println("Error creating stdout pipe:", err)
		return err, ""
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		println("Error creating stderr pipe:", err)
		return err, ""
	}

	var stdoutBuf bytes.Buffer
	var stderrBuf bytes.Buffer

	// Start the command
	if err = cmd.Start(); err != nil {
		println("Error starting command:", err)
		return err, ""
	}

	// Read and print stdout
	go func() {
		if _, err = io.Copy(&stdoutBuf, stdout); err != nil {
			println("Error copying stdout:", err)
		}
	}()

	// Read and print stderr
	go func() {
		if _, err = io.Copy(&stderrBuf, stderr); err != nil {
			println("Error copying stderr:", err)
		}
	}()

	// Wait for the command to finish
	if err = cmd.Wait(); err != nil {
		fmt.Println("Error waiting for command:", err)
	}
	// Print stdout and stderr separately
	fmt.Println("Standard Output:")
	fmt.Println(stdoutBuf.String())

	fmt.Println("Standard Err:")
	fmt.Println(stderrBuf.String())
	//fmt.Println(strings.Split(stderrBuf.String(), "\n")[1])

	res, isErr := identifyCommandLineArguments(stderrBuf.String(), path)
	if isErr && res != "" {
		fmt.Println("---return stderr")
		return errors.New(res), ""
	} else if !isErr && res != "" {
		return nil, res
	} else if stdoutBuf.Len() != 0 {
		fmt.Println("---return stdout")
		return nil, stdoutBuf.String()
	} else {
		fmt.Println("---stdoutBuf.Len()", stdoutBuf.Len())
		fmt.Println("---stdoutBuf.String()", stdoutBuf.String())
	}

	return nil, ""
}

func identifyCommandLineArguments(input string, path string) (string, bool) {
	// List of substrings to be trimmed
	//substrings := []string{"command-line-arguments", "# command-line-arguments"}
	tag := "command-line-arguments"
	var isStdErr bool
	input = strings.TrimSpace(input)
	if strings.Contains(input, tag) {
		fmt.Println("--- contain, input:", input)
		isStdErr = true
	}
	// split tmp dir message
	parts := strings.Split(input, "main.go")
	// Check if the split resulted in at least two parts
	if len(parts) > 1 {
		// The second part is the string after "main.go"
		input = path + parts[1]
		fmt.Println("Trimmed string:", input)
	} else {
		fmt.Println("String does not contain 'main.go'")
	}
	return input, isStdErr
}

// PrecompileBuildPackage tries to run `go build` against the precompiled .go files.
//
// This method is the most efficient to detect errors but requires that
// all the import are valid and available.
func PrecompileBuildPackage(fileOrPkg string, goBinary string) error {
	// TODO: use cmd/compile instead of exec?
	// TODO: find the nearest go.mod file, chdir in the same folder, rim prefix?
	// TODO: temporarily create an in-memory go.mod or disable go modules for gno?
	// TODO: ignore .go files that were not generated from gno?
	// TODO: automatically precompile if not yet done.

	files := []string{}

	info, err := os.Stat(fileOrPkg)
	if err != nil {
		return fmt.Errorf("invalid file or package path: %w", err)
	}
	if !info.IsDir() {
		file := fileOrPkg
		files = append(files, file)
	} else {
		pkgDir := fileOrPkg
		goGlob := filepath.Join(pkgDir, "*.go")
		goMatches, err := filepath.Glob(goGlob)
		if err != nil {
			return fmt.Errorf("glob: %w", err)
		}
		for _, goMatch := range goMatches {
			switch {
			case strings.HasPrefix(goMatch, "."): // skip
			case strings.HasSuffix(goMatch, "_filetest.go"): // skip
			case strings.HasSuffix(goMatch, "_filetest.gno.gen.go"): // skip
			case strings.HasSuffix(goMatch, "_test.go"): // skip
			case strings.HasSuffix(goMatch, "_test.gno.gen.go"): // skip
			default:
				files = append(files, goMatch)
			}
		}
	}

	sort.Strings(files)
	args := append([]string{"build", "-v", "-tags=gno"}, files...)
	cmd := exec.Command(goBinary, args...)
	rootDir, err := guessRootDir(fileOrPkg, goBinary)
	if err == nil {
		cmd.Dir = rootDir
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		fmt.Fprintln(os.Stderr, string(out))
		return fmt.Errorf("std go compiler: %w", err)
	}

	return nil
}

func precompileAST(fset *token.FileSet, f *ast.File, checkWhitelist bool) (ast.Node, error) {
	var errs error

	imports := astutil.Imports(fset, f)

	// import whitelist
	if checkWhitelist {
		for _, paragraph := range imports {
			for _, importSpec := range paragraph {
				importPath := strings.TrimPrefix(strings.TrimSuffix(importSpec.Path.Value, `"`), `"`)

				if strings.HasPrefix(importPath, GnoRealmPkgsPrefixBefore) {
					continue
				}

				if strings.HasPrefix(importPath, GnoPackagePrefixBefore) {
					continue
				}

				valid := false
				for _, whitelisted := range stdlibWhitelist {
					if importPath == whitelisted {
						valid = true
						break
					}
				}
				if valid {
					continue
				}

				for _, whitelisted := range importPrefixWhitelist {
					if strings.HasPrefix(importPath, whitelisted) {
						valid = true
						break
					}
				}
				if valid {
					continue
				}

				errs = multierr.Append(errs, fmt.Errorf("import %q is not in the whitelist", importPath))
			}
		}
	}

	// rewrite imports
	for _, paragraph := range imports {
		for _, importSpec := range paragraph {
			importPath := strings.TrimPrefix(strings.TrimSuffix(importSpec.Path.Value, `"`), `"`)

			// std package
			if importPath == GnoStdPkgBefore {
				if !astutil.RewriteImport(fset, f, GnoStdPkgBefore, GnoStdPkgAfter) {
					errs = multierr.Append(errs, fmt.Errorf("failed to replace the %q package with %q", GnoStdPkgBefore, GnoStdPkgAfter))
				}
			}

			// p/pkg packages
			if strings.HasPrefix(importPath, GnoPackagePrefixBefore) {
				target := GnoPackagePrefixAfter + strings.TrimPrefix(importPath, GnoPackagePrefixBefore)

				if !astutil.RewriteImport(fset, f, importPath, target) {
					errs = multierr.Append(errs, fmt.Errorf("failed to replace the %q package with %q", importPath, target))
				}
			}

			// r/realm packages
			if strings.HasPrefix(importPath, GnoRealmPkgsPrefixBefore) {
				target := GnoRealmPkgsPrefixAfter + strings.TrimPrefix(importPath, GnoRealmPkgsPrefixBefore)

				if !astutil.RewriteImport(fset, f, importPath, target) {
					errs = multierr.Append(errs, fmt.Errorf("failed to replace the %q package with %q", importPath, target))
				}
			}
		}
	}

	// custom handler
	node := astutil.Apply(f,
		// pre
		func(c *astutil.Cursor) bool {
			// do things here
			return true
		},
		// post
		func(c *astutil.Cursor) bool {
			// and here
			return true
		},
	)

	return node, errs
}
