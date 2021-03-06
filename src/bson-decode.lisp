(in-package :cl-mongo)

(defun ht->list.1 (ht)
  (let ((lst ()))
    (maphash (lambda (k v) (push v lst)) ht)
    (nreverse lst)))

(defun end-of-key (start array)
  (let ((eol start))
    (do ((pos start (+ pos 1))) 
	((= (elt array pos) 0))
      (incf eol))
    eol))

(defun bson-decode (totlen pos docs array &key (container #'ht->document.1))
  ;; FIXME refactor
  (let ((lst ()))
    (when (zerop docs) (return-from bson-decode lst))
    (tagbody
     start-document
       (let* ((ht (make-hash-table :test #'equal :size 10))
              (end (+ (- pos 1) (octet-to-int32.1 array pos)))) 
         (incf pos 4)
         (tagbody
          get-key-value
            (let* ((type (elt array pos))
                   (spos (+ pos 1))
                   (epos (end-of-key pos array))
                   (key (babel:octets-to-string array :start spos :end epos)))
              (setf pos (+ 1 epos))
              (cond
                ((= type +bson-data-number+)
                 (setf (gethash key ht) (decode-double-float-bits (octet-to-uint64.1 array pos)))
                 (incf pos 8))
                ((= type +bson-data-string+)
                 (let* ((size (octet-to-int32.1 array pos))
                        (npos (+ 4 pos))
                        (eos (+ 3 pos size)) ;;do not include null
                        (value (babel:octets-to-string array :start npos :end eos)))
                   (setf (gethash key ht) value)
                   (setf pos (+ 1 eos))))
                ((= type +bson-data-object+)
                 (let* ((size (octet-to-int32.1 array pos))
                        (eos (- (+ pos size) 1))) 
                   (if (> (elt array (+ pos 4)) 0)
                       (setf (gethash key ht) (car (bson-decode eos pos 1 array)))
                       (setf (gethash key ht) nil))
                   (setf pos (+ 1 eos))))
                ((= type +bson-data-array+)
                 (let* ((size (octet-to-int32.1 array pos))
                        (eos  (- (+ pos size) 1))) 
                   (if (> (elt array (+ pos 4)) 0)
                       (setf (gethash key ht) (car (bson-decode eos pos 1 array :container #'ht->list.1)))
                       (setf (gethash key ht) nil))
                   (setf pos (+ 1 eos))))
                ((= type +bson-data-binary+)
                 (let* ((binarysize (octet-to-int32.1 array pos))
                        (totalsize (+ 5 binarysize))
                        (type (elt array (+ 4 pos)))
                        (size (if (eql type #x02)
                                  (octet-to-int32.1 array (+ pos 5))
                                  (octet-to-int32.1 array pos)))
                        (offset (+ pos (if (eql type #x02) 9 5)))
                        (binary (bson-binary type (subseq array offset (+ offset size)))))
                   (setf (gethash key ht) binary)
                   (incf pos totalsize)))
                ((= type +bson-data-undefined+)
                 (setf (gethash key ht) nil))
                ((= type +bson-data-oid+)
                 (let ((npos  (+ pos 12)))
                   (setf (gethash key ht) (make-bson-oid :oid (subseq array pos npos))
                         pos npos)))
                ((= type +bson-data-boolean+)
                 (setf (gethash key ht) (byte-to-bool (elt array pos)))
                 (incf pos 1))
                ((= type +bson-data-date+)
                 (setf (gethash key ht) (make-bson-time (octet-to-uint64.1 array pos)))
                 (incf pos 8))  
                ((= type +bson-data-null+)
                 (setf (gethash key ht) nil))
                ((= type +bson-data-regex+)
                 (let* ((eregex    (end-of-key pos array))
                        (regex     (babel:octets-to-string array :start pos :end eregex))
                        (npos      (+ 1 eregex))
                        (eopt      (end-of-key npos array))
                        (options   (babel:octets-to-string array :start npos :end eopt)))
                   (setf (gethash key ht) (make-bson-regex regex options))
                   (setf pos (+ 1 eopt))))	
                ((= type +bson-data-dbpointer+)
                 (let ((npos  (+ pos 12)))
                   (setf (gethash key ht) (subseq array pos npos))
                   (setf pos npos)))
                ((= type +bson-data-code+)
                 (let* ((size (octet-to-int32.1 array pos))
                        (npos (+ 4 pos))
                        (eos  (+ 3 pos size)) ;;do not include null
                        (value  (babel:octets-to-string array :start npos :end eos)))
                   (setf (gethash key ht) value)
                   (setf pos (+ 1 eos))))
                ((= type +bson-data-symbol+)
                 (let* ((size (octet-to-int32.1 array pos))
                        (npos (+ 4 pos))
                        (eos  (+ 3 pos size)) ;;do not include null
                        (value  (babel:octets-to-string array :start npos :end eos)))
                   (setf (gethash key ht) value)
                   (setf pos (+ 1 eos))
                   (intern value :cl-user)))
                ((= type +bson-data-code_w_s+)
                 (let* ((total-size (octet-to-int32.1 array pos))
                        (npos (+ 4 pos))
                        (string-size (octet-to-int32.1 array npos))
                        (start-of-string (+ 4 npos))
                        (end-of-string   (+ 3 npos string-size)) ;;do not include null
                        (javascript      (babel:octets-to-string array :start start-of-string :end end-of-string))
                        (eojs            (+ 1 end-of-string))
                        (env             (car (bson-decode (+ pos total-size) eojs 1 array))))
                   (setf (gethash key ht) (list javascript env))
                   (incf pos total-size)))
                ((= type +bson-data-int32+)
                 (setf (gethash key ht) (octet-to-int32.1 array pos))
                 (incf pos 4))
                ((= type +bson-data-timestamp+)
                 (setf (gethash key ht) (octet-to-int64.1 array pos))
                 (incf pos 8))
                ((= type +bson-data-long+)
                 (setf (gethash key ht) (octet-to-int64.1 array pos))
                 (incf pos 8))
                ((= type +bson-data-min-key+)
                 (setf (gethash key ht) nil))
                ((= type +bson-data-max-key+)
                 (setf (gethash key ht) nil))
                (t (error "error : unable to process this type : ~A " type))) ;; end of condition on type
              (when (< pos end)
                (go get-key-value))))
         (incf pos)
         (push (funcall container ht) lst))
       (decf docs)
       (when (= totlen pos)
         (return-from bson-decode (nreverse lst)))
       (when (zerop docs)
         (return-from bson-decode (nreverse lst)))
       (go start-document))))

