;;
;; A compiler.
;;  $Id: comp.scm,v 1.1.2.4 2005-01-01 07:22:34 shirok Exp $

(define-module gauche.internal
  (use util.match)
  )
(select-module gauche.internal)

;; Entry
(define (compile program . opts)
  (let1 mod (get-optional opts #f)
    (if mod
      (let1 origmod (vm-current-module)
        (dynamic-wind
            (lambda () (vm-set-current-module mod))
            (lambda () (compile-int program '() 'tail))
            (lambda () (vm-set-current-module origmod))))
      (compile-int program '() 'tail))))

;; compile-int:: (Program, Env, Ctx) -> [Insn]
(define (compile-int program env ctx)
  (match program
    ((op . args)
     (if (variable? op)
       (let1 local (lookup-env op env #t)
         (cond
          ((vm-insn? local) ;; LREF
           (list local))
          ((is-a? local <macro>) ;; local macro
           (compile-int (call-macro-expander local program env) env ctx))
          ((get-global-binding op env)
           => (lambda (gloc)
                (let1 val (gloc-ref gloc)
                  (cond
                   ((is-a? val <syntax>)
                    (call-syntax-compiler val program env ctx))
                   ((is-a? val <macro>)
                    (compile-int (call-macro-expander val program env)
                                 env ctx))
                   (else
                    (compile-call (compile-varref op '()) args env ctx))))))
          (else
           (compile-call (compile-varref op '()) args env ctx))))
       (compile-call (compile-int op env 'normal) args env ctx)))
    ((? variable?)
     (compile-varref program env))
    (else
     (if (eq? ctx 'stmt) '() (list program)))
    ))

(define (compile-varref var env)
  (let1 loc (lookup-env var env #f)
    (if (variable? loc)
      (list (vm-insn-make 'GREF) loc)
      (list loc))))

(define (compile-call head args env ctx)
  (let ((argcode (compile-args args env))
        (numargs (length args)))
    (case ctx
      ((tail)
       `(,(vm-insn-make 'PRE-TAIL numargs)
         ,@argcode
         ,@head
         ,(vm-insn-make 'TAIL-CALL numargs)))
      (else
       `(,(vm-insn-make 'PRE-CALL numargs)
         (,@argcode ,@head ,(vm-insn-make 'CALL numargs)))))))

(define (compile-args args env)
  (if (null? args)
    '()
    `(,@(compile-int (car args) env 'normal)
      ,(vm-insn-make 'PUSH)
      ,@(compile-args (cdr args) env))))

;; Look up local environment
;;
(define (lookup-env var env syntax?)
  (let outer ((env env)
              (depth 0))
    (if (pair? env)
      (let ((var (if (and (identifier? var)
                          (eq? (ref var 'env) env))
                   (slot-ref var 'name)
                   var))
            (frame (car env)))
        (if (eq? (car frame) #t)
          ;; macro binding.
          (if syntax?
            (or (find (lambda (p) (eq? var (car p))) (cdr frame))
                (outer (cdr env) (+ depth 1)))
            (outer (cdr env) (+ depth 1)))
          ;; look for variable binding.  there may be a case that
          ;; single frame contains more than one variable with the
          ;; same name (in the case like '(let* ((x 1) (x 2)) ...)'),
          ;; so we have to scan the frame until the end. */
          (let inner ((frame frame) (offset 0) (found #f))
            (cond ((null? frame)
                   (if found
                     (vm-insn-make 'LREF depth (- offset found 1))
                     (outer (cdr env) (+ depth 1))))
                  ((eq? (car frame) var)
                   (inner (cdr frame) (+ offset 1) offset))
                  (else
                   (inner (cdr frame) (+ offset 1) found))))
          ))
      ;; binding not found in local env.  returns an identifier.
      (if (and (symbol? var) (not syntax?))
        (make-identifier var '())
        var))))

(define (get-global-binding name env)
  (cond
   ((identifier? name)
    (find-binding (slot-ref name 'module) (slot-ref name 'name) #f))
   ((symbol? name)
    (find-binding (get-current-module env) name #f))
   (else #f)))

(define (get-current-module env)
  (vm-current-module))

;;============================================================
;; Special forms
;;

(define (syntax-if form env ctx)
  (match form
    ((if test then else)
     (let ((test-code (compile-int test env 'normal))
           (then-code (compile-int then env ctx))
           (else-code (compile-int else env ctx)))
       (if (eq? ctx tail)
         (append test-code
                 (cons '(IF) test-code)
                 else-code)
         (let1 merger (list (list 'MNOP))
           (append test-code
                   (cons '(IF) (append test-code merger))
                   (append else-code merger))))))
    ((if test then)
     (syntax-if `(if ,test ,then (undefined))))
    (else
     (error "syntax error:" form))))
       


        
;;============================================================
;; Utilities
;;

(define (variable? arg)
  (or (symbol? arg) (identifier? arg)))

(define (find pred lis)
  (let loop ((lis lis))
    (cond ((null? lis) #f)
          ((pred (car lis)))
          (else (loop (cdr lis))))))

(define (fold proc seed lis)
  (let loop ((lis lis) (seed seed))
    (if (null? lis)
      seed
      (loop (cdr lis) (proc (car lis) seed)))))

(define (append-map proc lis)
  (apply append (map proc lis)))

;; return the last cdr of improper list.
;; when applied to compiler env, this returns a module.
(define (last-cdr lis)
  (let loop ((lis lis))
    (if (pair? lis) (loop (cdr lis)) lis)))
