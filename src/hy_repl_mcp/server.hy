#!/usr/bin/env hy
(import os)
(import pathlib)
(import subprocess)
(import sys)
(require hyrule *)
(import fastmcp [FastMCP])
(import hy_repl_mcp.common [Err Ok Running Stopped bind-result read-frame result-or-raise write-frame])

(setv mcp (FastMCP :name "hy-repl"))
(setv worker (Stopped))
(setv worker-path
  (as-> __file__ path
    (pathlib.Path path)
    (.resolve path)
    (getattr path "parent")
    (.joinpath path "worker.hy")
    (str path)))


(defn resolve-project [project]
  (as-> project path
    (pathlib.Path path)
    (.expanduser path)
    (.resolve path)
    (str path)))


(defn terminate-worker [worker-state]
  (match worker-state
    (Running worker-process)
      (do
        (try
          (doto worker-process
            (.terminate)
            (.wait))
          (except [exception Exception]
            None))
        (Stopped))
    (Stopped) (Stopped)))


(defn stop-worker []
  (global worker)
  (setv worker (terminate-worker worker)))


(do
  (defn project-venv [project-path]
    "项目的虚拟环境目录；没有则返回 None。"
    (let [candidate (.joinpath (pathlib.Path project-path) ".venv")]
      (if (.is-dir candidate) candidate None)))

  (defn venv-bin [venv-path]
    (str (.joinpath venv-path (if (= os.name "nt") "Scripts" "bin"))))

  (defn project-python [project-path]
    "项目解释器；项目虚拟环境优先，否则沿用服务进程解释器。"
    (let [venv (project-venv project-path)]
      (if venv
        (let [bin-path (pathlib.Path (venv-bin venv))
              candidates (if (= os.name "nt")
                           [(.joinpath bin-path "python.exe")
                            (.joinpath bin-path "python")]
                           [(.joinpath bin-path "python")
                            (.joinpath bin-path "python3")])]
          (str (or (next (gfor candidate candidates :if (.is-file candidate) candidate) None)
                   (getattr sys "executable"))))
        (getattr sys "executable"))))

  (defn worker-environment [project-path]
    (let [existing (.get os.environ "PYTHONPATH" "")
          python-path (+ project-path (if existing (+ os.pathsep existing) ""))
          environment (dict os.environ)
          venv (project-venv project-path)]
      (when venv
        (let [bin-path (venv-bin venv)
              current-path (.get environment "PATH" "")]
          (.update environment {"VIRTUAL_ENV" (str venv)
                                "PATH" (+ bin-path
                                         (if current-path
                                           (+ os.pathsep current-path)
                                           ""))})))
      (.update environment {"PYTHONPATH" python-path})
      environment)))


(defn launch-worker [project-path]
  (try
    (Ok
      (subprocess.Popen
        [(project-python project-path) "-m" "hy" worker-path]
        :cwd project-path
        :env (worker-environment project-path)
        :stdin subprocess.PIPE
        :stdout subprocess.PIPE
        :stderr None))
    (except [exception Exception]
      (Err (+ "Could not start Hy worker: " (str exception))))))


(defn worker-ready-result [worker-process]
  (bind-result (read-frame worker-process.stdout "Hy worker")
    (fn [payload]
      (match (= payload b"ready")
        True (Ok worker-process)
        False (Err "Hy worker did not become ready.")))))


(defn start-worker [project-path]
  (let [directory-result
        (match (.is-dir (pathlib.Path project-path))
          True (Ok project-path)
          False (Err (+ "project directory does not exist: " project-path)))]
    (bind-result directory-result
      (fn [_]
        (bind-result (launch-worker project-path)
          (fn [worker-process]
            (let [ready-result (worker-ready-result worker-process)]
              (match ready-result
                (Ok _) (Ok (Running worker-process))
                (Err message)
                  (do
                    (terminate-worker (Running worker-process))
                    (Err message))))))))))


(defn read-evaluation-frames [worker-process]
  (let [stdout-result (read-frame worker-process.stdout "Hy worker")]
    (bind-result stdout-result
      (fn [stdout-frame]
        (let [stderr-result (read-frame worker-process.stdout "Hy worker")]
          (bind-result stderr-result
            (fn [stderr-frame]
              (Ok {"stdout" (.decode stdout-frame "utf-8")
                   "stderr" (.decode stderr-frame "utf-8")}))))))))


(defn evaluate-worker [worker-process expr]
  (bind-result (write-frame worker-process.stdin (.encode expr "utf-8"))
    (fn [_]
      (read-evaluation-frames worker-process))))


(defn current-worker-result []
  (match worker
    (Running worker-process) (Ok worker-process)
    (Stopped) (Err "Call start_server before eval.")))


(defn [(mcp.tool "start_server")] #^ str start-server [#^ str project]
  "Start a Hy REPL worker in project."
  (global worker)
  (stop-worker)
  (setv worker (result-or-raise (start-worker (resolve-project project))))
  "Hy REPL started.")


(defn [(mcp.tool "eval")] #^ dict evaluate [#^ str expr]
  "Evaluate Lisp code in the Hy REPL and return its stdout and stderr."
  (result-or-raise
    (bind-result (current-worker-result)
      (fn [worker-process] (evaluate-worker worker-process expr)))))


(defn [(mcp.tool "stop_server")] #^ str stop-server []
  "Stop the Hy REPL worker."
  (stop-worker)
  "Hy REPL stopped.")


(defn main []
  (mcp.run))


(defmain []
  (main))
