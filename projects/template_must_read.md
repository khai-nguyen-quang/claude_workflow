
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

## Unit test (if any)
<unit_test_framework>


## Integration test (if any)
<itest_framework>

## Others

1. 

2. 