;;
;;  Generate uvutil.c
;;  $Id: uvutil.c.scm,v 1.2 2002-06-19 01:58:47 shirok Exp $

(use srfi-13)
(define (pr . args)  (for-each print args))
(define (spr . args) (string-join args "\n"))

;;==========================================================
;; prologue
;;

(pr
 "/*"
 " * uvutil - additional uniform vector utilities"
 " *"
 " *  Copyright(C) 2002 by Shiro Kawai (shiro@acm.org)"
 " *"
 " *  Permission to use, copy, modify, distribute this software and"
 " *  accompanying documentation for any purpose is hereby granted,"
 " *  provided that existing copyright notices are retained in all"
 " *  copies and that this notice is included verbatim in all"
 " *  distributions."
 " *  This software is provided as is, without express or implied"
 " *  warranty.  In no circumstances the author(s) shall be liable"
 " *  for any damages arising out of the use of this software."
 " *"
 " * This file is automatically generated from uvutil.c.scm"
 " * $Id: uvutil.c.scm,v 1.2 2002-06-19 01:58:47 shirok Exp $"
 " */"
 ""
 "#include <stdlib.h>"
 "#include <math.h>"
 "#include <limits.h>"
 "#include <string.h>  /* for memcpy() */"
 "#include <gauche.h>"
 "#include <gauche/extend.h>"
 "#include \"gauche/uvector.h\""
 "#include \"gauche/arith.h\""
 "#include \"uvectorP.h\""
 ""
 "#define SIZECHK(d, a, b)                                        \\"
 "  do {                                                          \\"
 "    if ((a)->size != (b)->size) {                               \\"
 "      Scm_Error(\"Vector size doesn't match: %S and %S\", a, b);  \\"
 "    }                                                           \\"
 "  SCM_ASSERT((a)->size == (d)->size);                         \\"
 "  } while (0)"
 ""
 ;; Common overflow handler
 "static void uvoverflow(void)"
 "{"
 "  Scm_Error(\"uniform vector operation overflow\");"
 "}"
 ""
 ;; u_long multiplier
 "static u_long umul(u_long x, u_long y, int clamp)"
 "{"
 "  u_long r;"
 "  if (x==0 || y==0) return 0;"
 "  r = x*y;"
 "  if (r<x || r<y) {"
 "    if (clamp) return SCM_ULONG_MAX;"
 "    else uvoverflow();"
 "  }"
 "  return r;"
 "}"
 ""
 )

(define *uvinfo*
  ;; tag    : s8, u64, etc.
  ;; ctype  : to be used to create C type and function name of the vector.
  ;; mtype  : to be used to create C macro name of the vector
  ;; etype  : C type name of element of the vector
  ;; otype  : C type name of C variables to operate on the elements of the
  ;;          vector.
  '((s8  S8Vector  S8VECTOR  "signed char"        int)
    (u8  U8Vector  U8VECTOR  "unsigned char"      int)
    (s16 S16Vector S16VECTOR "signed short"       int)
    (u16 U16Vector U16VECTOR "unsigned short"     int)
    (s32 S32Vector S32VECTOR "SCM_UVECTOR_INT32"  long)
    (u32 U32Vector U32VECTOR "SCM_UVECTOR_UINT32" u_long)
    (s64 S64Vector S64VECTOR "SCM_UVECTOR_INT64"  "SCM_UVECTOR_INT64")
    (u64 U64Vector U64VECTOR "SCM_UVECTOR_UINT64" "SCM_UVECTOR_UINT64")
    (f32 F32Vector F32VECTOR "float"              float)
    (f64 F64Vector F64VECTOR "double"             double)
    ))

(define (ctype-of tag)
  (cond ((assq tag *uvinfo*) => cadr)
        (else (error "bad tag" tag))))

(define (mtype-of tag)
  (cond ((assq tag *uvinfo*) => caddr)
        (else (error "bad tag" tag))))

(define (etype-of tag)
  (cond ((assq tag *uvinfo*) => cadddr)
        (else (error "bad tag" tag))))

(define (otype-of tag)
  (cond ((assq tag *uvinfo*) => (lambda (p) (list-ref p 4)))
        (else (error "bad tag" tag))))

;;=================================================================
;; Template for binary operation
;;

(define (emit-binop tag opname emit-operate)
  (pr
   #`"ScmObj Scm_,(ctype-of tag),|opname|(Scm,(ctype-of tag) *dst,"
   #`"                                    Scm,(ctype-of tag) *v0,"
   #`"                                    ScmObj operand,"
   #`"                                    int clamp)"
   #`"{"
   #`"    int i, size = v0->size;"
   #`"    ,(otype-of tag) k;"
   #`"    if (SCM_,(mtype-of tag)P(operand)) {"
   #`"        Scm,(ctype-of tag) *v1 = SCM_,(mtype-of tag)(operand);"
   #`"        SIZECHK(dst, v0, v1);"
   #`"        for (i=0; i<size; i++) {"
   #`"            ,(emit-operate \"k\" \"v0->elements[i]\" \"v1->elements[i]\");"
   #`"            dst->elements[i] = (,(etype-of tag))k;"
   #`"        }"
   #`"    } else {"
   #`"        ,(etype-of tag) e1;"
   #`"        SCM_ASSERT(dst->size == v0->size);"
   #`"        SCM_,(mtype-of tag)_UNBOX(e1, operand);"
   #`"        for (i=0; i<size; i++) {"
   #`"             ,(emit-operate \"k\" \"v0->elements[i]\" \"e1\");"
   #`"             dst->elements[i] = (,(etype-of tag))k;"
   #`"        }"
   #`"    }"
   #`"    return SCM_OBJ(dst);"
   #`"}"))

;; handle overflow or underflow
(define (overflow maxval)
  #`"do { if (!(clamp&SCM_UVECTOR_CLAMP_HI)) uvoverflow();\n (k)=,|maxval|; } while (0)")

(define (underflow minval)
  #`"do { if (!(clamp&SCM_UVECTOR_CLAMP_LO)) uvoverflow();\n (k)=,|minval|; } while (0)")

;; Common part for s8, u8, s16, u16vector.
;; Can be used for s32 and u32 vector on 64bit architecture.
(define (emit-small-binop tag opname op minval maxval)
  (emit-binop tag opname
              (lambda (k e0 e1)
                (spr
                 #`"do { ,k = ,e0 ,op ,e1 ;"
                 #`"  if (,k < ,minval)      ,(underflow minval);"
                 #`"  else if (,k > ,maxval) ,(overflow maxval);"
                 #`"} while(0)")))
  )

(define (emit-noclamp-binop tag opname op)
  (emit-binop tag opname
              (lambda (k e0 e1)
                (spr #`",k = ,e0 ,op ,e1")))
  )

(define (emit-small-ops tag minval maxval)
  (emit-small-binop tag "Add" "+" minval maxval)
  (emit-small-binop tag "Sub" "-" minval maxval)
  (emit-small-binop tag "Mul" "*" minval maxval)
  (emit-small-binop tag "Div" "/" minval maxval)
  (emit-noclamp-binop tag "Mod" "%")
  (emit-noclamp-binop tag "And" "&")
  (emit-noclamp-binop tag "Ior" "|")
  (emit-noclamp-binop tag "Xor" "^")
  )

(emit-small-ops 's8    -128    127)
(emit-small-ops 'u8       0    255)
(emit-small-ops 's16 -32768  32767)
(emit-small-ops 'u16      0  65535)

;; Operation on the machine-word-size value.
;; Special treatment is required to detect overflow and underflow.
;; These are so terrible.
(define (add-signed-words k e0 e1)
  (define (over)  (overflow "LONG_MAX"))
  (define (under) (underflow "LONG_MIN"))
  (spr
   #`"do { long V0 = ,|e0|, V1= ,|e1|;"
   #`"  ,k = V0 + V1;"
   #`"  if (V0 >= 0) { if (V1 >= 0 && ,k < V0) ,(over); }"
   #`"  else {         if (V1 < 0 && ,k >= V0) ,(under); }"
   #`"} while (0)"))

(define (add-unsigned-words k e0 e1)
  (spr
   #`"do { u_long V0 = ,|e0|, V1 = ,|e1|, C = 0;"
   #`"    UADD(,k, C, V0, V1);"
   #`"    if (C) ,(overflow \"SCM_ULONG_MAX\");"
   #`"} while (0)"))

(define (bignumop op tag)
  (lambda (k e0 e1)
    (spr 
     #`"do { ,k = Scm_,|op|2(,|e0|, ,|e1|);"
     #`"  if (Scm_NumCmp(,k, Scm_Uvector,|tag|Min) < 0)"
     #`"     ,(underflow #`\"Scm_Uvector,|tag|Min\");"
     #`"  if (Scm_NumCmp(,k, Scm_Uvector,|tag|Max) > 0)"
     #`"     ,(overflow #`\"Scm_Uvector,|tag|Max\");"
     #`" } while (0)")))

(define add-signed-bignum64   (bignumop "Add" "S64"))
(define add-unsigned-bignum64 (bignumop "Add" "U64"))

(define (sub-signed-words k e0 e1)
  (define (over)  (overflow "LONG_MAX"))
  (define (under) (underflow "LONG_MIN"))
  (spr
   #`"do { long V0 = ,|e0|, V1= ,|e1|;"
   #`"  ,k = V0 - V1;"
   #`"  if (V0 >= 0) { if (V1 < 0 && ,k < V0) ,(over); }"
   #`"  else {         if (V1 > 0 && ,k >= V0) ,(under); }"
   #`"} while (0)"))

(define (sub-unsigned-words k e0 e1)
  (spr
   #`"do { u_long V0 = ,|e0|, V1 = ,|e1|, C = 0;"
   #`"    USUB(,k, C, V0, V1);"
   #`"    if (C) ,(underflow 0);"
   #`"} while (0)"))

(define sub-signed-bignum64   (bignumop "Subtract" "S64"))
(define sub-unsigned-bignum64 (bignumop "Subtract" "U64"))

(define (mul-signed-words k e0 e1)
  (define (over)  (overflow "LONG_MAX"))
  (define (under) (underflow "LONG_MIN"))
  (spr
   #`"do { long V0 = ,|e0|, V1 = ,|e1|;"
   #`"  u_long kr;"
   #`"  if (V0 >= 0) {"
   #`"    if (V1 >= 0) {"
   #`"      kr = umul(V0, V1, (clamp&SCM_UVECTOR_CLAMP_HI));"
   #`"      if (kr > LONG_MAX) ,(over);"
   #`"      else ,k = kr;"
   #`"    } else {"
   #`"      kr = umul(V0, -V1, (clamp&SCM_UVECTOR_CLAMP_LO));"
   #`"      if (kr > LONG_MAX+1UL) ,(under);"
   #`"      else ,k = -kr;"
   #`"    }"
   #`"  } else {"
   #`"    if (V1 >= 0) {"
   #`"      kr = umul(-V0, V1, (clamp&SCM_UVECTOR_CLAMP_LO));"
   #`"      if (kr > LONG_MAX+1UL) ,(under);"
   #`"      else ,k = -kr;"
   #`"    } else {"
   #`"      kr = umul(-V0, -V1, (clamp&SCM_UVECTOR_CLAMP_HI));"
   #`"      if (kr > LONG_MAX) ,(over);            \\"
   #`"      else ,k = kr;"
   #`"    }"
   #`"  }"
   #`"} while (0)"))

(define (mul-unsigned-words k e0 e1)
  (spr
   #`"do { u_long V0 = ,|e0|, V1 = ,|e1|, hi, lo;"
   #`"  UMUL(hi, lo, V0, V1);"
   #`"  if (hi) ,(overflow \"SCM_ULONG_MAX\");"
   #`"  else ,k = lo;"
   #`"} while (0)"))

(define mul-signed-bignum64   (bignumop "Multiply" "S64"))
(define mul-unsigned-bignum64 (bignumop "Multiply" "U64"))

(define (div-signed-words k e0 e1)
  (spr
   #`"do { long V0 = ,|e0|, V1 = ,|e1|;"
   #`"  if ((V0 == LONG_MIN && V1 == -1)"
   #`"      || (V1 == LONG_MIN && V0 == -1)) {"
   #`"    ,(overflow 'LONG_MAX);"
   #`"  }"
   #`"  ,k = V0/V1;"
   #`"} while (0)"))

(define (div-unsigned-words k e0 e1)
  #`",k = ,e0 / ,e1")

(define (div-signed-bignum64 k e0 e1)
  (spr 
   #`"do { ,k = Scm_Quotient(,|e0|, ,|e1|, NULL);"
   #`"  if (Scm_NumCmp(,k, Scm_UvectorS64Max) > 0)"
   #`"     ,(overflow #`\"Scm_UvectorS64Max\");"
   #`" } while (0)"))

(define (div-unsigned-bignum64 k e0 e1)
  #`",k = Scm_Quotient(,|e0|, ,|e1|, NULL);")

(define (mod-bignum64 k e0 e1)  #`",k = Scm_Modulo(,|e0|, ,|e1|, FALSE)")
(define (and-bignum64 k e0 e1)  #`",k = Scm_LogAnd(,|e0|, ,|e1|)")
(define (ior-bignum64 k e0 e1)  #`",k = Scm_LogIor(,|e0|, ,|e1|)")
(define (xor-bignum64 k e0 e1)  #`",k = Scm_LogXor(,|e0|, ,|e1|)")

;; s32 vector.  
(define (emit-s32-ops)
  (define int32min (- (expt 2 31)))
  (define int32max (- (expt 2 31) 1))
  ;; on 64bit architecture, overflow detection is simple.
  (print "#if SIZEOF_LONG >= 8")
  (emit-small-binop 's32 "Add" "+" int32min int32max)
  (emit-small-binop 's32 "Sub" "-" int32min int32max)
  (emit-small-binop 's32 "Mul" "*" int32min int32max)
  (emit-small-binop 's32 "Div" "/" int32min int32max)
  (print "#else /*SIZEOF_LONG == 4*/")
  ;; on 32bit architecture, needs some hack to detect overflow.
  (emit-binop 's32 "Add" add-signed-words)
  (emit-binop 's32 "Sub" sub-signed-words)
  (emit-binop 's32 "Mul" mul-signed-words)
  (emit-binop 's32 "Div" div-signed-words)
  (print "#endif /*SIZEOF_LONG == 4 */")
  ;; common 
  (emit-noclamp-binop 's32 "Mod" "%")
  (emit-noclamp-binop 's32 "And" "&")
  (emit-noclamp-binop 's32 "Ior" "|")
  (emit-noclamp-binop 's32 "Xor" "^")
  )

;; u32 vector
(define (emit-u32-ops)
  (define uint32max "4294967295UL")
  ;; on 64bit architecture, overflow detection is simple.
  (print "#if SIZEOF_LONG >= 8")
  (emit-small-binop 'u32 "Add" "+" 0 uint32max)
  (emit-small-binop 'u32 "Sub" "-" 0 uint32max)
  (emit-small-binop 'u32 "Mul" "*" 0 uint32max)
  (emit-small-binop 'u32 "Div" "/" 0 uint32max)
  (print "#else /*SIZEOF_LONG == 4*/")
  ;; on 32bit architecture, needs some hack to detect overflow.
  (emit-binop 'u32 "Add" add-unsigned-words)
  (emit-binop 'u32 "Sub" sub-unsigned-words)
  (emit-binop 'u32 "Mul" mul-unsigned-words)
  (emit-noclamp-binop 'u32 "Div" "/")
  (print "#endif /*SIZEOF_LONG == 4 */")
  ;; common
  (emit-noclamp-binop 'u32 "Mod" "%")
  (emit-noclamp-binop 'u32 "And" "&")
  (emit-noclamp-binop 'u32 "Ior" "|")
  (emit-noclamp-binop 'u32 "Xor" "^")
  )

;; s64 vector
(define (emit-s64-ops)
  (define int64min (- (expt 2 63)))
  (define int64max (- (expt 2 63) 1))
  (print "#if SIZEOF_LONG > 8")
  ;; if long is 128bit or more....
  (emit-small-binop 's64 "Add" "+" int64min int64max)
  (emit-small-binop 's64 "Sub" "-" int64min int64max)
  (emit-small-binop 's64 "Mul" "*" int64min int64max)
  (emit-small-binop 's64 "Div" "/" int64min int64max)
  (emit-noclamp-binop 's64 "Mod" "%")
  (emit-noclamp-binop 's64 "And" "&")
  (emit-noclamp-binop 's64 "Ior" "|")
  (emit-noclamp-binop 's64 "Xor" "^")
  (print "#elif SIZEOF_LONG == 8")
  ;; full-word arithmetic
  (emit-binop 's64 "Add" add-signed-words)
  (emit-binop 's64 "Sub" sub-signed-words)
  (emit-binop 's64 "Mul" mul-signed-words)
  (emit-binop 's64 "Div" div-signed-words)
  (emit-noclamp-binop 's64 "Mod" "%")
  (emit-noclamp-binop 's64 "And" "&")
  (emit-noclamp-binop 's64 "Ior" "|")
  (emit-noclamp-binop 's64 "Xor" "^")
  (print "#else /* SIZEOF_LONG == 4 */")
  ;; on 32bit architecture, needs some hack to detect overflow.
  (emit-binop 's64 "Add" add-signed-bignum64)
  (emit-binop 's64 "Sub" sub-signed-bignum64)
  (emit-binop 's64 "Mul" mul-signed-bignum64)
  (emit-binop 's64 "Div" div-signed-bignum64)
  (emit-binop 's64 "Mod" mod-bignum64)
  (emit-binop 's64 "And" and-bignum64)
  (emit-binop 's64 "Ior" ior-bignum64)
  (emit-binop 's64 "Xor" xor-bignum64)
  (print "#endif /*SIZEOF_LONG == 4 */")
  )

;; u64 vector
(define (emit-u64-ops)
  (define uint64max #`",(- (expt 2 64) 1)UL")
  (print "#if SIZEOF_LONG > 8")
  ;; if long is 128bit or more....
  (emit-small-binop 'u64 "Add" "+" 0 uint64max)
  (emit-small-binop 'u64 "Sub" "-" 0 uint64max)
  (emit-small-binop 'u64 "Mul" "*" 0 uint64max)
  (emit-small-binop 'u64 "Div" "/" 0 uint64max)
  (emit-noclamp-binop 'u64 "Mod" "%")
  (emit-noclamp-binop 'u64 "And" "&")
  (emit-noclamp-binop 'u64 "Ior" "|")
  (emit-noclamp-binop 'u64 "Xor" "^")
  (print "#elif SIZEOF_LONG == 8")
  ;; full-word arithmetic
  (emit-binop 'u64 "Add" add-unsigned-words)
  (emit-binop 'u64 "Sub" sub-unsigned-words)
  (emit-binop 'u64 "Mul" mul-unsigned-words)
  (emit-binop 'u64 "Div" div-unsigned-words)
  (emit-noclamp-binop 'u64 "Mod" "%")
  (emit-noclamp-binop 'u64 "And" "&")
  (emit-noclamp-binop 'u64 "Ior" "|")
  (emit-noclamp-binop 'u64 "Xor" "^")
  (print "#else /* SIZEOF_LONG == 4 */")
  ;; on 32bit architecture, needs some hack to detect overflow.
  (emit-binop 'u64 "Add" add-unsigned-bignum64)
  (emit-binop 'u64 "Sub" sub-unsigned-bignum64)
  (emit-binop 'u64 "Mul" mul-unsigned-bignum64)
  (emit-binop 'u64 "Div" div-unsigned-bignum64)
  (emit-binop 'u64 "Mod" mod-bignum64)
  (emit-binop 'u64 "And" and-bignum64)
  (emit-binop 'u64 "Ior" ior-bignum64)
  (emit-binop 'u64 "Xor" xor-bignum64)
  (print "#endif /*SIZEOF_LONG == 4 */")
  )

(emit-s32-ops)
(emit-u32-ops)
(emit-s64-ops)
(emit-u64-ops)

;; f32 and f64 vector
(define (emit-f32-ops)
  (emit-noclamp-binop 'f32 "Add" "+")
  (emit-noclamp-binop 'f32 "Sub" "-")
  (emit-noclamp-binop 'f32 "Mul" "*")
  (emit-noclamp-binop 'f32 "Div" "/")
  )

(define (emit-f64-ops)
  (emit-noclamp-binop 'f64 "Add" "+")
  (emit-noclamp-binop 'f64 "Sub" "-")
  (emit-noclamp-binop 'f64 "Mul" "*")
  (emit-noclamp-binop 'f64 "Div" "/")
  )

(emit-f32-ops)
(emit-f64-ops)