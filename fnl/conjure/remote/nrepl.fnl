(module conjure.remote.nrepl
  {require {a conjure.aniseed.core
            net conjure.net
            timer conjure.timer
            uuid conjure.uuid
            log conjure.log
            client conjure.client
            extract conjure.extract
            bencode conjure.remote.transport.bencode}})

(defn with-all-msgs-fn [cb]
  (let [acc []]
    (fn [msg]
      (table.insert acc msg)
      (when msg.status.done
        (cb acc)))))

(defn connect [opts]
  "Connects to a remote nREPL server.
  * opts.host: The host string.
  * opts.port: Port as a string.
  * opts.on-failure: Function to call after a failed connection with the error.
  * opts.on-success: Function to call on a successful connection.
  * opts.on-error: Function to call when we receive an error (passed as argument) or a nil response.
  * opts.default-callback: Function to call when the user didn't provide a callback to their send.
  * opts.on-message: Function to call when we receive a message after the callback for the message is invoked.
  Returns a connection table containing a `destroy` function."
  (let [state {:message-queue []
               :awaiting-process? false
               :bc (bencode.new)
               :msgs {}}]

    (var conn
      {:session nil
       :state state})

    (fn enrich-status [msg]
      (let [ks (a.get msg :status)
            status {}]
        (a.run!
          (fn [k]
            (a.assoc status k true))
          ks)
        (a.assoc msg :status status)
        msg))

    (fn send [msg cb]
      (let [msg-id (uuid.v4)]
        (a.assoc msg :id msg-id)
        (when (and (not msg.session) conn.session)
          (a.assoc msg :session conn.session))
        (log.dbg "send" msg)
        (a.assoc-in state [:msgs msg-id]
                    {:msg msg
                     :cb (or cb (fn []))
                     :sent-at (os.time)})
        (conn.sock:write (bencode.encode msg))
        nil))

    (fn process-message [err chunk]
      (if
        err (opts.on-error err)
        (not chunk) (opts.on-error)
        (->> (bencode.decode-all state.bc chunk)
             (a.run!
               (fn [msg]
                 (log.dbg "receive" msg)
                 (enrich-status msg)

                 (when msg.status.need-input
                   (client.schedule
                     (fn []
                       (send {:op :stdin
                              :stdin (.. (or (extract.prompt "Input required: ")
                                             "")
                                         "\n")
                              :session msg.session}))))

                 (let [cb (a.get-in state [:msgs msg.id :cb] opts.default-callback)
                       (ok? err) (pcall cb msg)]
                   (when (not ok?)
                     (opts.on-error err)))

                 (when msg.status.done
                   (a.assoc-in state [:msgs msg.id] nil))

                 (opts.on-message msg))))))

    (fn process-message-queue []
      (set state.awaiting-process? false)
      (when (not (a.empty? state.message-queue))
        (let [msgs state.message-queue]
          (set state.message-queue [])
          (a.run!
            (fn [args]
              (process-message (unpack args)))
            msgs))))

    (fn enqueue-message [...]
      (table.insert state.message-queue [...])
      (when (not state.awaiting-process?)
        (set state.awaiting-process? true)
        (client.schedule process-message-queue)))

    (fn handle-connect-fn []
      (client.schedule-wrap
        (fn [err]
          (if err
            (opts.on-failure err)

            (do
              (conn.sock:read_start (client.wrap enqueue-message))
              (opts.on-success))))))

    (set conn
         (a.merge!
           conn
           {:send send}
           (net.connect
             {:host opts.host
              :port opts.port
              :cb (handle-connect-fn)})))

    conn))
