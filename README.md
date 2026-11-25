# hy-repl-mcp

A FastMCP server that keeps a Hy REPL worker for each project.

## Run

```console
$ uvx hy-repl-mcp
```

The package can also be installed with `pip`; `uvx` is not a runtime
dependency.

## Tools

- `start_server(project)` starts a persistent Hy REPL for a project.
- `eval(expr)` evaluates Hy code and returns its `stdout` and `stderr`.
- `stop_server()` stops the REPL worker.
