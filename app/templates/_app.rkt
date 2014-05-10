#lang racket

(require "src/spin/main.rkt")
(require db
         json
         web-server/servlet
         web-server/servlet-env
         web-server/http/bindings
         web-server/http/request-structs
         net/url-structs)
(require racquel)

(define con-pool
  (connection-pool
    (lambda () (sqlite3-connect #:database "my.db"))
    #:max-idle-connections 10))

(define (json-response-maker status headers obj)
  (response status
            (status->message status)
            (current-seconds)
            #"application/json; charset=utf-8"
            headers
            (if (eq? obj '())
              (lambda (op) '())
              ; get the first hash-value since the hash-key is the class
              (let ([jsexpr-body (car (hash-values (data-object->jsexpr obj)))])
                (lambda (op) (write-json (force jsexpr-body) op))))))

(define (json-list-response-maker status headers objs)
  (response status
            (status->message status)
            (current-seconds)
            #"application/json; charset=utf-8"
            headers
            ; get the first hash-value since the hash-key is the class
            (let ([jsexpr-body (map (lambda (obj) (car (hash-values (data-object->jsexpr obj)))) objs)])
              (lambda (op) (write-json (force jsexpr-body) op)))))

(define (get-json path handler)
  (define-handler "GET" path handler json-response-maker))

(define (get-json-list path handler)
  (define-handler "GET" path handler json-list-response-maker))

(define (post-json path handler)
  (define-handler "POST" path handler json-response-maker))

(define (put-json path handler)
  (define-handler "PUT" path handler json-response-maker))

(define (delete-json path handler)
  (define-handler "DELETE" path handler json-response-maker))

<% _.each(entities, function (entity) { %>
(define (initialize-<%= entity.name %>! con)
  (unless (table-exists? con "<%= pluralize(entity.name) %>")
    (query-exec con 
      (string-append
        "CREATE TABLE <%= pluralize(entity.name) %> ("
        <% _.each(attrs, function (attr) { %>
        "<%= attr.attrName %> <%= attr.attrImplType %>,"<% }); %>
        "id INTEGER PRIMARY KEY AUTOINCREMENT)"))))

(define <%= entity.name %>%
  (data-class object%
    (table-name "<%= pluralize(entity.name) %>")
    (column (id #f "id")
            <% _.each(entity.attrs, function (attr) { %>
            (<%= attr.attrName %> <%= attr.attrDefault %> "<%= attr.attrName %>")<% }); %> 
    )
    (primary-key id #:autoincrement #t)
    (super-new)))

(get-json-list "/<%= baseName %>/<%= pluralize(entity.name) %>" 
  (lambda (req)
    (let ([con (connection-pool-lease con-pool)])
    `(200 () ,(select-data-objects con <%= entity.name %>%)))))

(get-json "/<%= baseName %>/<%= pluralize(entity.name) %>/:id"
  (lambda (req)
    (let* ([con (connection-pool-lease con-pool)]
           [obj (select-data-objects con <%= entity.name %>% (where (= id ?)) (params req 'id))])
      (if (eq? obj '())
        `(404 () ())
        (car obj)))))

(post-json "/<%= baseName %>/<%= pluralize(entity.name) %>"
  (lambda (req)
    (let* ([con (connection-pool-lease con-pool)]
           [json (bytes->jsexpr (request-post-data/raw req))]
           [obj (jsexpr->data-object (hasheq  (string->symbol (get-field external-name (get-class-metadata-object <%= entity.name %>%))) json))])
      (insert-data-object con obj)
      `(201 () ,obj))))

(put-json "/<%= baseName %>/<%= pluralize(entity.name) %>/:id"
  (lambda (req)
    (let* ([con (connection-pool-lease con-pool)]
           [json (bytes->jsexpr (request-post-data/raw req))]
           [newobj (jsexpr->data-object (hasheq  (string->symbol (get-field external-name (get-class-metadata-object <%= entity.name %>%))) json))]
           [obj (select-data-objects con <%= entity.name %>% (where (= id ?)) (params req 'id))])
      (if (eq? obj '())
        `(404 () ())
        (begin
          (set-column! id newobj (params req 'id))
          (update-data-object con newobj)
          newobj)))))

(delete-json "/<%= baseName %>/<%= pluralize(entity.name) %>/:id"
  (lambda (req)
    (let* ([con (connection-pool-lease con-pool)]
           [obj (select-data-objects con <%= entity.name %>% (where (= id ?)) (params req 'id))])
      (if (eq? obj '())
        `(404 () ())
        (begin
          (delete-data-object con (car obj))
          `(204 () ()))))))
<% }); %>

<% if (entities.length > 0) { %>
(let ([con (connection-pool-lease con-pool)])
<% _.each(entities, function (entity) { %>
  (initialize-<%= entity.name %>! con)<% }); %>
  (disconnect con))<% }; %>
(run #:port 8080 #:extra-files-paths (list (build-path "public")))

