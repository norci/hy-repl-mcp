#!/usr/bin/env hy
(import asyncio)
(import os)
(import pathlib)
(import sys)
(import tempfile)
(import hy)
(import fastmcp [Client])
(import fastmcp.client.transports [StdioTransport])

(setv source-root (.joinpath (get (getattr (.resolve (pathlib.Path __file__)) "parents") 1) "src"))


(defn package-environment []
  (setv environment (dict os.environ))
  (try
    (import hy_repl_mcp)
    (except [ModuleNotFoundError]
      (.insert sys.path 0 (str source-root))
      (.update
        environment
        {"PYTHONPATH"
         (.rstrip
           (str.join os.pathsep [(str source-root) (.get environment "PYTHONPATH" "")])
           os.pathsep)})))
  environment)


(defn check-explicit-state-types []
  (import hy_repl_mcp.server)
  (setv server-module hy_repl_mcp.server)
  (assert (isinstance server-module.worker server-module.Stopped))
  (assert (isinstance (server-module.Ok "value") server-module.Ok))
  (assert (isinstance (server-module.Err "message") server-module.Err)))


(defn check-result [result expected]
  (assert (= (getattr result "is_error" False) (= (get expected 0) :error)))
  (match expected
    [:error] None
    [:text text]
    (assert (= (. (get result.content 0) text) text))
    [:output stdout stderr]
    (assert (= (getattr result "structured_content" None)
               {"stdout" stdout "stderr" stderr}))
    [:stderr fragment]
    (do
      (setv output (getattr result "structured_content" None))
      (assert (= (get output "stdout") ""))
      (assert (in fragment (get output "stderr"))))))

(defn eval-case [expr expected]
  ["eval" {"expr" expr} expected])


(defn :async check-package [environment]
  (import hy_repl_mcp.server :as server)
  (with [workspace (tempfile.TemporaryDirectory)]
    (let [project (.joinpath (pathlib.Path workspace) "project")
          server-directory (.joinpath (pathlib.Path workspace) "server")
          marker (.joinpath (pathlib.Path workspace) "venv-used")
          make-venv-python
          (fn [project marker]
            (let [bin-directory (.joinpath project ".venv" "bin")
                  python (.joinpath bin-directory "python")
                  script (+ "#!/bin/sh\n"
                            "printf 'used\\n' > '" (str marker) "'\n"
                            "exec '" (str hy.sys_executable) "' \"$@\"\n")]
              (.mkdir bin-directory :parents True)
              (.write-text python script)
              (.chmod python 0o755)
              python))]
      (.mkdir project)
      (.mkdir server-directory)
      (.write-text (.joinpath project "probe_module.py") "VALUE = 42\n")
      (assert (= (server.project-python (str project))
                 (getattr sys "executable")))
      (let [venv-python (make-venv-python project marker)]
        (assert (= (server.project-python (str project)) (str venv-python))))
      (let [shadow-package (.joinpath project "hy_repl_mcp")]
        (.mkdir shadow-package)
        (.write-text (.joinpath shadow-package "__init__.py") "raise RuntimeError(\"target project shadowed hy_repl_mcp\")\n"))
      (let [transport (StdioTransport :command (get sys.orig_argv 0)
                                      :args ["-m" "hy_repl_mcp"]
                                      :cwd server-directory
                                      :env environment)]
        (with [:async client (Client transport)]
          (assert (= (set (lfor tool (await (.list-tools client)) (. tool name)))
                     (set ["start_server" "eval" "stop_server"])))
          (setv cases
                [(eval-case "(+ 1 2)" [:error])
                 ["start_server" {"project" (str project)} [:text "Hy REPL started."]]
                 (eval-case "(+ 1 2)" [:output "3\n" ""])
                 (eval-case "(+ 40 2)" [:output "42\n" ""])
                 (eval-case "(import probe_module)" [:output "" ""])
                 (eval-case "(print probe_module.VALUE)" [:output "42\n" ""])
                 (eval-case "(/ 1 0)"
                            [:stderr "ZeroDivisionError: division by zero"])
                 ["stop_server" {} [:text "Hy REPL stopped."]]])
          (for [[name arguments expected] cases]
            (check-result
              (await (.call-tool client name arguments :raise-on-error False))
              expected))
          (assert (.is-file marker)))))))


(defn main []
  (setv environment (package-environment))
  (check-explicit-state-types)
  (asyncio.run (check-package environment))
  (print "PASS"))


(when (= __name__ "__main__")
  (main))
