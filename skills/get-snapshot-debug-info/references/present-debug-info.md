# Presenting Debug Info

After fetching the debug info and variables, present the exception details, call stack, and variable values as a human-readable report.

## Interpreting the response

### Exception info fields

- **`exceptionInfo.Id`**: The fully qualified exception type (e.g., `System.NullReferenceException`).
- **`exceptionInfo.Description`**: The exception message.
- **`exceptionInfo.Code`**: The native exception code (e.g., `3221225477` = `0xC0000005` for access violation).

### Stack frame fields

- **`Name`**: Fully qualified method name (e.g., `MyApp.Controllers.HomeController.Index()`).
- **`File`**: Source file name (may be null for framework/third-party code).
- **`Line`**: Line number in the source file (may be null).
- **`Variables`**: Array of variable indices for this frame. Empty for frames without captured variables.

### Variable fields

- **`name`**: Variable name (e.g., `this`, `request`, `count`).
- **`type`**: Type name (e.g., `HomeController`, `string`, `int`).
- **`value`**: Display value (e.g., `"hello"`, `42`, `{MyApp.Models.User}`). Objects show their type in braces.
- **`children`**: Indices of child variables (properties/fields of the object). Use to expand nested details.

## Display format

Present as a structured report with the exception at the top, followed by the call stack with variables.

Example output:

```
=== Snapshot Debug Info ===
Exception: System.NullReferenceException (Code: 0x80004003)
Description: Object reference not set to an instance of an object.

=== Call Stack ===
  [0] MyApp.Controllers.HomeController.Index() — HomeController.cs:42
      Variables:
        this (HomeController) = {MyApp.Controllers.HomeController}
        request (HttpRequest) = {Microsoft.AspNetCore.Http.DefaultHttpRequest}
          └─ Path (string) = "/api/users"
          └─ Method (string) = "GET"
          └─ ContentLength (long?) = null
  [1] Microsoft.AspNetCore.Mvc.Internal.ControllerActionInvoker.InvokeActionMethodAsync()
      (framework — 5 variables available, skipped)
  [2] Microsoft.AspNetCore.Mvc.Internal.ResourceInvoker.InvokeNextResourceFilter()
      (framework — 6 variables available, skipped)
  ...

Fetched variables for 1 user code frame(s). Skipped 2 framework frame(s).
To inspect a specific framework frame's variables, ask to expand frame [1] or [2].
```

### Formatting rules

1. **Exception header**: Show exception type, code (in hex), and description.
2. **Stack frames**: Number with `[0]`, `[1]`, etc. Show method name, file, and line separated by ` — `.
3. **User code frames** (with source file info): Show variables indented under the frame with `name (type) = value` format. These are the most relevant for root-cause analysis.
4. **Framework frames** (no source file): List the method name but skip variable fetching. Show `(framework — N variables available, skipped)` to indicate variables exist but were not fetched. The user can request expansion of specific framework frames if needed.
5. **Child variables**: Further indent with `└─` prefix for children (level 2).
6. **No variables**: Show `(none)` for frames without captured variables.
7. **Hex code**: Convert the exception code to hex for readability: `"0x" + [Convert]::ToString($code, 16).ToUpper()`.

### Summary

After the call stack, provide a brief analysis:
1. **Exception**: What type of exception occurred and what it means.
2. **Location**: Which method and line number threw the exception (the top frame with source info).
3. **Key variables**: Any variable values that point to the root cause (e.g., null references, unexpected values).
4. **Recommendation**: If the source code is available, suggest a specific fix.
