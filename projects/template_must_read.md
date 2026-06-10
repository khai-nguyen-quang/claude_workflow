
# Abbreviation
This is abbreviation for claude agent to extract information correctly. 
Content of <project>_must_read.md starts from `# Setup instructions`
| command         | purpose                                             |
| :---------------| :---------------------------------------------------|
| <git_clone_cmd> | git command to clone project source code |
| <compile_cmd>   | bash command to compile source code      |
| <unit_tests_all>   | bash command to run all unit tests at once      |
| <unit_tests_file>   | bash command to run a specific unit test file |
| <itest_all>   | bash command to run all integration tests at once      |
| <itest_file>   | bash command to run a particular integration test at once      |
| <lint_all>   | bash command to run a specific unit test file |
| <lint_file>   | bash command to run a specific unit test file |

From claude code, run `/wf collect <project>` to generate <project>_must_read.md file

---

# Setup instructions
## Source code download
```bash 
# Download project code with command : 
<git_clone_cmd>
```

## Compilation
```bash
# Compile with following command
cd <project>
<compile_cmd>
```

## Run unit tests
```bash
`cd <project>`
# Run all unit tests
<unit_tests_all>

# Run a particular tests
<unit_tests_file>
```

## Run integration tests
```bash
cd <project>
# Run all itest tests
<itest_all>

# Run a particular tests
<itest_file>
```

## Run lint
```bash
cd <project>
# Run all lint
<lint_all>

# Run a particular tests
<lint_file>
```

## Run other tests
`cd <project>`
`<other_tests>`
`cd ../`

---

<span style="color:red">***User puts project specific info from here***</span>

# Technical note

> Single source of binding constraints. The `/wf` skill forwards one subsection to each
> agent: **Features** → planning / plan-review / review; **Coding and Testing** → coding /
> test / lint / fix_review; debug reads the whole note. Keep the heading names exactly so
> the forwarder can find them. Put every must-honor rule under the matching subsection.

## Features
<!-- For planning & review agents: product/domain behavior and feature constraints that
     decide WHAT to build — e.g. nuisance-alert rules, safety behaviors, UX requirements. -->
1.

2.

## Coding and Testing
<!-- For coding & testing agents: the rules for HOW to build and verify. Examples:
     - All build/test/lint go through `./dev.sh` (never call scons/pytest/clang-tidy directly).
     - Language standard / toolchain (e.g. C++20, Clang 14).
     - Build artifacts location (e.g. build/<arch>/<config>/ via VariantDir — never in source tree).
     - Lint policy (e.g. never `lint --all`; lint changed files explicitly).
     - Unit test framework: <unit_test_framework>
     - Integration test framework: <itest_framework> -->
1.

2.

## Others
<!-- Anything not covered above; read by all agents. -->
1.

2.