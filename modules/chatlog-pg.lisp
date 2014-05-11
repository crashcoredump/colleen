#|
  This file is a part of Colleen
  (c) 2013 TymoonNET/NexT http://tymoon.eu (shinmera@tymoon.eu)
  Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package :org.tymoonnext.colleen)
(defpackage org.tymoonnext.colleen.mod.chatlog-pg
  (:use :cl :colleen :events))
(in-package :org.tymoonnext.colleen.mod.chatlog-pg)

(define-module chatlog-pg ()
  ((%lock :initform (bordeaux-threads:make-lock "DB") :accessor lock))
  (:documentation "Logs messages in channels to a database."))

(defmethod start ((chatlog chatlog-pg))
  (connect-db chatlog))

(defmethod stop ((chatlog chatlog-pg))
  (disconnect-db chatlog))

(defclass chatlog ()
  ((server :col-type (string 36) :initarg :server :accessor r-server)
   (channel :col-type (string 36) :initarg :channel :accessor r-channel)
   (user :col-type (string 36) :initarg :user :accessor r-user)
   (time :col-type integer :initarg :time :accessor r-time)
   (type :col-type (string 1) :initarg :type :accessor r-type)
   (message :col-type text :initarg :message :accessor r-message))
  (:metaclass postmodern:dao-class))

(defmethod connect-db ((chatlog chatlog-pg) &key db host port user pass)
  (with-module-storage (chatlog)
    (let ((db (or db (uc:config-tree :db)))
          (host (or host (uc:config-tree :host)))
          (port (or port (uc:config-tree :port)))
          (user (or user (uc:config-tree :user)))
          (pass (or pass (uc:config-tree :pass))))
      (v:info :chatlog-pg "Connecting ~a@~a:~a/~a" user host port db)
      (postmodern:connect-toplevel db user pass host :port port)
      (unless (postmodern:table-exists-p 'chatlog)
        (postmodern:execute (postmodern:dao-table-definition 'chatlog))))))

(defmethod disconnect-db ((chatlog chatlog-pg))
  (v:info :chatlog-pg "Disconnecting.")
  (postmodern:disconnect-toplevel))

(defconstant +UNIX-EPOCH-DIFFERENCE+ (encode-universal-time 0 0 0 1 1 1970 0))
(defmethod insert-record ((chatlog chatlog-pg) server channel user type message)
  (with-module-storage (chatlog)
    (when (find (format NIL "~a/~a" server channel) (uc:config-tree :active-in) :test #'string-equal)
      (v:trace :chatlog-pg "Logging event from ~a/~a <~a> (~a)" server channel user type)
      (postmodern:insert-dao (make-instance 'chatlog :server (princ-to-string server) :channel channel :user user
                                                     :time (- (get-universal-time) +UNIX-EPOCH-DIFFERENCE+)
                                                     :type type :message message)))))

(define-group chatlog-pg :documentation "Change chatlog-pg settings.")

(define-command (chatlog-pg activate) (&optional channel server) (:authorization T :documentation "Activate logging for a channel." :modulevar chatlog)
  (unless channel (setf channel (channel event)))
  (unless server (setf server (name (server event))))
  (pushnew (format NIL "~a/~a" server channel) (uc:config-tree :active-in) :test #'string-equal)
  (respond event "Activated logging for ~a/~a" server channel))

(define-command (chatlog-pg deactivate) (&optional channel server) (:authorization T :documentation "Deactivate logging for a channel." :modulevar chatlog)
  (unless channel (setf channel (channel event)))
  (unless server (setf server (name (server event))))
  (setf (uc:config-tree :active-in)
        (delete (format NIL "~a/~a" server channel) (uc:config-tree :active-in) :test #'string-equal))
  (respond event "Deactivated logging for ~a/~a" server channel))

(define-command (chatlog-pg reconnect) (&optional db host port user pass) (:authorization T :documentation "Restart connection to the database." :modulevar chatlog)
  (disconnect-db chatlog)
  (connect-db chatlog 
              :db db 
              :host host 
              :port (when port (parse-integer port)) 
              :user user 
              :pass pass))

(define-handler (privmsg-event event) (:modulevar chatlog)
  (if (and (> (length (message event)) (length " ACTION ")) (string= (message event) "ACTION" :start1 1 :end1 7))
      (insert-record chatlog (name (server event)) (channel event) (nick event) "a" (format NIL " * ~a" (subseq (message event) 7)))
      (insert-record chatlog (name (server event)) (channel event) (nick event) "m" (message event))))

(define-handler (send-event event) (:modulevar chatlog)
  (insert-record chatlog (name (server event)) (channel event) (nick event) "m" (message event)))

(define-handler (nick-event event) (:modulevar chatlog)
  (dolist (channel (channels (server event)))
    (insert-record chatlog (name (server event)) channel (nick event) "n" (format NIL " ** NICK ~a" (new-nick event)))))

(define-handler (quit-event event) (:modulevar chatlog)
  (dolist (channel (channels (server event)))
    (insert-record chatlog (name (server event)) channel (nick event) "q" (format NIL " ** QUIT ~a" (reason event)))))

(define-handler (part-event event) (:modulevar chatlog)
  (insert-record chatlog (name (server event)) (channel event) (nick event) "p" " ** PART"))

(define-handler (join-event event) (:modulevar chatlog)
  (insert-record chatlog (name (server event)) (channel event) (nick event) "j" " ** JOIN"))

(define-handler (kick-event event) (:modulevar chatlog)
  (insert-record chatlog (name (server event)) (channel event) (nick event) "k" (format NIL " ** KICK ~a (~a)" (target event) (reason event))))

(define-handler (mode-event event) (:modulevar chatlog)
  (insert-record chatlog (name (server event)) (target event) (nick event) "o" (format NIL " ** MODE ~a ~a" (mode event) (parameter event))))

(define-handler (topic-event event) (:modulevar chatlog)
  (insert-record chatlog (name (server event)) (channel event) (channel event) "t" (format NIL " ** TOPIC ~a" (topic event))))

(define-handler (topic-set-event event) (:modulevar chatlog)
  (insert-record chatlog (name (server event)) (channel event) (nick event) "t" (format NIL " ** TOPIC ~a" (topic event))))

(defun pstmt (statement &rest vars)
  (apply (postmodern:prepare statement) vars))

(defun fmt (unix)
  (if unix
      (local-time:format-timestring NIL (local-time:unix-to-timestamp unix) :format '((:year 4) #\. (:month 2) #\. (:day 2) #\Space (:hour 2) #\: (:min 2) #\: (:sec 2)))
      "never"))

(define-command (chatlog-pg stats) (&optional server channel) (:documentation "Retrieve short statistics about the recorded chatlog history.")
  (if (and server channel)
      (let ((server (string-downcase server))
            (channel (string-downcase channel)))
        (let ((events   (first (first (pstmt "SELECT COUNT(*) FROM \"chatlog\" WHERE lower(\"server\")=$1 AND lower(\"channel\")=$2" server channel))))
              (users    (length (pstmt "SELECT \"user\" FROM \"chatlog\" WHERE lower(\"server\")=$1 AND lower(\"channel\")=$2 GROUP BY \"user\"" server channel)))
              (messages (first (first (pstmt "SELECT COUNT(*) FROM \"chatlog\" WHERE lower(\"server\")=$1 AND lower(\"channel\")=$2 AND \"type\"='m'" server channel))))
              (since    (first (first (pstmt "SELECT \"time\" FROM \"chatlog\" WHERE lower(\"server\")=$1 AND lower(\"channel\")=$2 ORDER BY \"time\" ASC LIMIT 1" server channel))))
              (topuser  (first (pstmt "SELECT COUNT(*) AS c,user FROM \"chatlog\" WHERE lower(\"server\")=$2 AND lower(\"channel\")=$1 AND \"type\"='m' GROUP BY \"user\" ORDER BY c DESC" server channel))))
          (respond event "Logging since ~a with a total of ~d events from ~a users, of which ~d were messages. User with most messages (~d) is ~a."
                   (fmt since) events users messages (first topuser) (string-trim " " (second topuser)))))
      (let ((channels (length (postmodern:query "SELECT \"channel\" FROM \"chatlog\" GROUP BY \"channel\"")))
            (events   (first (first (postmodern:query "SELECT COUNT(*) FROM \"chatlog\""))))
            (users    (length (postmodern:query "SELECT \"user\" FROM \"chatlog\" GROUP BY \"user\"")))
            (messages (first (first (postmodern:query "SELECT COUNT(*) FROM \"chatlog\" WHERE \"type\"='m'"))))
            (topuser  (first (postmodern:query "SELECT COUNT(*) AS c,\"user\" FROM \"chatlog\" WHERE \"type\"='m' GROUP BY \"user\" ORDER BY c DESC LIMIT 1"))))
        (respond event "Logging ~d channels with a total of ~d events from ~a users, of which ~d were messages. User with most messages (~d) is ~a."
                 channels events users messages (first topuser) (string-trim " " (second topuser))))))

(define-command (chatlog-pg count) (nick) (:documentation "Counts the amount of recorded messages for a nick.")
  (setf nick (string-downcase nick))
  (let ((events   (first (first (pstmt "SELECT COUNT(*) FROM \"chatlog\" WHERE lower(\"user\")=$1" nick))))
        (since    (first (first (pstmt "SELECT \"time\" FROM \"chatlog\" WHERE lower(\"user\")=$1 ORDER BY \"time\" ASC LIMIT 1" nick))))
        (messages (first (first (pstmt "SELECT COUNT(*) FROM \"chatlog\" WHERE lower(\"user\")=$1 AND \"type\"='m'" nick))))
        (channels (length (pstmt "SELECT COUNT(*) FROM \"chatlog\" WHERE lower(\"user\")=$1 GROUP BY \"channel\"" nick))))
    (respond event "First recorded ~a on ~a. Since then, ~a has ~d events on record, of which ~d were messages across ~d channels."
             nick (fmt since) nick events messages channels)))
