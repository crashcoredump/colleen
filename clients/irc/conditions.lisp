#|
 This file is a part of Colleen
 (c) 2015 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.colleen.clients.irc)

(define-condition message-condition (condition)
  ((message :initarg :message :reader message)))

(define-condition message-too-long-warning (warning message-condition)
  ()
  (:report (lambda (c s)
             (declare (ignore c))
             (format s "Message exceeds length limit of ~a." *send-length-limit*))))