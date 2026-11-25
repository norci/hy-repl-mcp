(import dataclasses [dataclass])
(require hyrule *)

(defclass WorkerState [])
(defclass [(dataclass :frozen True)] Stopped [WorkerState])
(defclass [(dataclass :frozen True)] Running [WorkerState] #^ object process)
(defclass Result [])
(defclass [(dataclass :frozen True)] Ok [Result] #^ object value)
(defclass [(dataclass :frozen True)] Err [Result] #^ object message)

(defn bind-result [result continuation]
  (match result
    (Ok value) (continuation value)
    (Err message) result))

(defn result-or-raise [result]
  (match result
    (Ok value) value
    (Err message) (raise (RuntimeError message))))

(defn parse-frame-size [header source]
  (try
    (Ok (int (.strip header)))
    (except [ValueError]
      (Err (+ source " sent an invalid frame header.")))))

(defn decode-frame [size payload source]
  (match (= (len payload) size)
    True (Ok payload)
    False (Err (+ source " sent a truncated frame."))))

(defn read-frame [stream source]
  (let [header (.readline stream)]
    (match header
      b"" (Err (+ source " stopped."))
      _ (bind-result (parse-frame-size header source)
          (fn [size] (decode-frame size (.read stream size) source))))))

(defn write-frame [stream payload]
  (let [header (-> payload len str (+ (chr 10)) (.encode "utf-8"))]
    (try
      (do (doto stream (.write header) (.write payload) (.flush)) (Ok None))
      (except [exception Exception]
        (Err (+ "Worker communication failed: " (str exception)))))))
