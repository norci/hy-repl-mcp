#!/usr/bin/env hy
(import contextlib)
(import io)
(import pathlib)
(import sys)
(import hy.repl [REPL])
(require hyrule *)
(import hyrule [recur])

(setv package-root
  (as-> __file__ path
    (pathlib.Path path)
    (.resolve path)
    (getattr path "parent")
    (getattr path "parent")
    (str path)))
(.insert sys.path 0 package-root)

(import hy_repl_mcp.common [Ok bind-result read-frame write-frame])


(defn evaluate [repl source]
  (let [stdout-captured (io.StringIO)
        stderr-captured (io.StringIO)
        incomplete (with [_ (contextlib.redirect-stdout stdout-captured)
                          _ (contextlib.redirect-stderr stderr-captured)]
                     (.runsource repl source))]
    (Ok [incomplete (.getvalue stdout-captured) (.getvalue stderr-captured)])))


(defn next-pending [pending source incomplete]
  (if incomplete
    (+ pending source)
    ""))


(defn process-request [repl output-stream pending request]
  (let [source (.decode request "utf-8")]
    (bind-result (evaluate repl (+ pending source))
      (fn [evaluation]
        (let [incomplete (get evaluation 0)
              stdout (get evaluation 1)
              stderr (get evaluation 2)]
          (bind-result (write-frame output-stream (.encode stdout "utf-8"))
            (fn [_]
              (bind-result (write-frame output-stream (.encode stderr "utf-8"))
                (fn [_]
                  (Ok (next-pending pending source incomplete)))))))))))


(defn serve [repl input-stream output-stream]
  (bind-result (write-frame output-stream b"ready")
    (fn [_]
      (loop [[pending ""]]
        (bind-result (read-frame input-stream "MCP server")
          (fn [request]
            (bind-result (process-request repl output-stream pending request)
              (fn [next-state]
                (recur next-state)))))))))


(defn main []
  (let [input-stream sys.stdin.buffer
        output-stream sys.stdout.buffer
        repl (REPL :locals {"__name__" "__hy_repl_worker__"})]
    (serve repl input-stream output-stream)))


(defmain []
  (main))
