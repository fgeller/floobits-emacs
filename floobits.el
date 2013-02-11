(require 'json)

(setq floobits-agent-version "0.01")
(setq floobits-agent-host "localhost")
(setq floobits-agent-port 4567)
(setq floobits-change-set ())
(setq floobits-agent-buffer "")
(setq floobits-room-owner "kans")

(defcustom floobits-username "kans"
  "Username for floobits"
  :type 'string
  )

(defcustom floobits-secret "1aiwkewqzwauexwnmqk9u9q3c"
  "Secret for floobits"
  :type 'string
  )

(defcustom floobits-room "asdf"
  "Room for floobits"
  :type 'string
  )

(defcustom floobits-share-dir "~/share"
  "Room for floobits"
  :type 'string)

(defun floobits-filter-func (condp lst)
  (delq nil
  (mapcar (lambda (x) (and (funcall condp x) x)) lst)))

(defun _floobits-is-buffer-public(buf)
  (let ((name (buffer-name buf)))
    (cond
     ((string="*" (substring name 0 1)) nil)
     ((string=" " (substring name 0 1)) nil)
     ((< (length name) 11) t)
     ((string= "floobits.el" (substring name 0 11)) nil)
     (t t))))

(defun _floobits-is-buffer-shared(buf)
  (let ((name (buffer-name buf))
  (length (length floobits-share-dir)))
    (cond
     ((not (boundp floobits-share-dir)) nil)
     ((< (length name) length) nil)
     (string= floobits-share-dir (substring name 0 length) t)
     (t nil))))

(defun floobits-get-public-buffers ()
  "returns buffers that aren't internal to emacs"
  (floobits-filter-func '_floobits-is-buffer-public (buffer-list)))

(defun floobits-get-buffer-text (buffer)
  "returns properties free text of buffer with name (name)"
  (with-current-buffer buffer)
  ; (with-current-buffer (set-buffer (get-buffer-create name))
    (buffer-substring-no-properties (point-min) (point-max)))

(defun floobits-event-disconnect (req)
  (message "Disconnected: %s" (cdr (assoc "reason" req))))

(defun floobits-event-room_info (req)
  "does a thing")
  ;(mapcar 'floobits-get-buffer-text (floobits-get-public-buffers)))
;    (req (list `(buffers . ,buffers))))
 ;   (send-to-agent req 'buffer-list)))

(defun floobits-event-join (req))

(defun floobits-event-part (req))

(defun floobits-event-edit (req)
  (message "got an edit event %s" req)
  (let* ((filename (cdr (assoc "full_path" req)))
    (buf (get-file-buffer filename))
    (edits (cdr (assoc "edits" req)))
    (apply-edit (lambda (edit)
      (let* ((inhibit-modification-hooks t)
        (edit-start (+ 1 (elt edit 0)))
        (edit-length (elt edit 1))
        (edit-end (min (+ 1 (buffer-size)) (+ edit-start edit-length))))
        (message "deleting region from %s to %s" edit-start edit-end)
        (delete-region edit-start edit-end)
        (when (eq 3 (length edit))
          (message "inserting %s" (elt edit 2))
          (goto-char edit-start)
          (insert (elt edit 2)))))))
    (if buf
      (with-current-buffer buf
        (save-excursion
          (atomic-change-group
            (mapcar apply-edit edits)))))))

(defun floobits-event-get_buf (req)
  (let ((filename (cdr (assoc "full_path" req))))
    (if (not (eq filename nil))
      (find-file filename)
    (message "filename does not exist for buffer %s" (cdr (assoc "id" req))))))

(defun floobits-switch (text)
  (let* ((json-key-type 'string)
   (req (json-read-from-string text))
   (event (cdr (assoc "name" req)))
   (func (concat "floobits-event-" event)))
    (funcall (read func) req)))

(defun floobits-listener(process response)
  (setq floobits-agent-buffer (concat floobits-agent-buffer response))
  (let ((position (search "\n" floobits-agent-buffer)))
    (when position
      (floobits-switch (substring floobits-agent-buffer 0 position))
      (setq floobits-agent-buffer
      (substring floobits-agent-buffer
        (if (> (length floobits-agent-buffer) position) (+ 1 position) position)))
      (floobits-listener process ""))))

(defun floobits-auth()
  (let ((req (list
    (cons 'username floobits-username)
    (cons 'room floobits-room)
    (cons 'secret floobits-secret)
    (cons 'room_owner floobits-room-owner))))
    (send-to-agent req 'auth)))

(defun create-connection()
  (setq floo (open-network-stream "floobits" nil floobits-agent-host floobits-agent-port))
  (set-process-coding-system floo 'utf-8 'utf-8)
  (set-process-filter floo 'floobits-listener)
  (floobits-auth))

(defun change-func (var begin end &optional &rest old_length)
  "does stuff"
  (setq contents (buffer-substring-no-properties begin end))
  (set var
       (mapcar 'symbol-value '(begin end contents old_length))))

(defun send-to-agent (req event)
  (add-to-list 'req (cons 'version floobits-agent-version))
  (add-to-list 'req (cons 'name event))
  (process-send-string floo (concat (json-encode req) "\n")))

(defun get-text (begin end)
  (buffer-substring-no-properties begin end))

(defun before-change (begin end)
  (if (eq (_floobits-is-buffer-public (current-buffer)) t)
    (let ((text (floobits-get-buffer-text (current-buffer))))
      (add-to-list 'floobits-change-set (cons 'before text)))))

(defun after-change (begin end old_length)
  (if (eq (_floobits-is-buffer-public (current-buffer)) t)
     (let ((text (floobits-get-buffer-text (current-buffer))))
      (add-to-list 'floobits-change-set (cons 'after text))
      (add-to-list 'floobits-change-set (cons 'full_path (buffer-file-name (current-buffer))))
      (send-to-agent floobits-change-set 'change)
    (setq floobits-change-set))))

(defun after-new-buffer ()
  (let ((req '("event" "new-buffer")))
    (add-to-list 'req (cons 'text (get-text point-min point-max)))
    (add-to-list 'req (cons 'path (file-name-directory load-file-name)))
    (send-to-agent req 'new-buffer)))

;;(add-hook 'before-change-functions 'before-change nil nil)
(add-hook 'after-change-functions 'after-change nil nil)
(add-hook 'find-file-hook 'after-new-buffer nil t)

(create-connection)
