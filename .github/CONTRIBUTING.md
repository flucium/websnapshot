## Contributing Code
...

## Pull requests
...

## Issues rule
...

## Git commit rule
These are the rules for using Git commands such as "git add" and "git commit".

### Action
(e.g. `git add ...`)
| # | purpose |
| ------------- | ------------- |
| add | Add file contents to the index.|
| mv | Move or rename a file, a directory, or a symlink. Using "git add" together with "git rm" is also acceptable, but "git mv" is preferred whenever possible. |
| rm | Remove files from the working tree and from the index. e.g. file: `git rm ./test.txt`, directory: `git rm -r ./abcd/`  |

### Commit and commit message, description
(e.g. `git commit -m "..." -m "...."`)
| # | message | description | note |
| ------------- | ------------- | ------------- | ------------- |
| add  | Describe the action you performed and include the affected file path. (Example: `git commit -m "add ./test.txt"`)  | Provide a clear description of the changes you made. Explain the purpose of the changes when necessary. <br>(Examples: <br>- Pattern 1: `-m "added an empty test file."`. <br>- Pattern 2: `-m "added an empty test file. This file is used by ./src/main.c to read and write test data."`) | Use add only when adding new files. Do not use it for adding features or functionality. |
| update | Same as above. | Same as above. | Use update for enhancements that improve functionality rather than fixing bugs. For bug fixes, use fix instead. |
| fix | Same as above. | Same as above. | Use fix for bug fixes. You may also use it for functionality or performance changes that are directly related to fixing a bug. Do not use “fix” for general feature changes or performance improvements.
| refactor | Same as above. | Same as above. | Use the refactor for removing unnecessary code, deleting commented-out code, and making changes that do not affect functionality or performance, such as formatting or code cleanup. Use the "update" or "fix" for changes that improve performance or otherwise modify the behavior of the code. |
| rename | Same as above. | Same as above. | Use rename when changing the file path of code, whether by using "git mv" or by moving files with "git add" and "git rm". (Use rename for file name changes as well.) |
| remove (rm is also acceptable) | Same as above. | Same as above. | Use remove for deleting files or directories. "rm" is also acceptable, but "remove" is recommended. Do not use "remove" for deleting code within a file, such as removing functions. Those changes should be treated as modifications instead. |
| other | Same as above. | Same as above. | Use other only when none of the other categories apply. Frequent use of “other” is discouraged. |

Keep the “commit message” concise. Include only the affected file path or other information that identifies the change. 

Use the “description” to explain the changes in detail.

When necessary, explain why the commit is categorized as `add`, `update`, `fix`, or another commit type.

#### Git commit example
```bash
$ git add ./Arithmetic.swift
$ git commit -m "add ./Arithmetic.swift" -m "added ./Arithmetic.swift. This file contains functions for basic arithmetic operations. At present, it provides addition (`func plus(...)`) and subtraction (`func minus(...)`). Function parameters and implementation details are omitted for brevity."
```
