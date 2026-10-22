#!/usr/bin/env python3
"""
Flux VM Self-Test
Tests every opcode for correctness.

Copyright (C) 2026 Karac V. Thweatt
"""

import sys
import os
import tempfile
sys.path.insert(0, os.path.dirname(__file__))

from fvm import FluxVM, Val, TTag, Op, Instr, StructLayout, VMError


# ---------------------------------------------------------------------------
# Test harness
# ---------------------------------------------------------------------------

_passed = 0
_failed = 0

def test(name, fn):
    global _passed, _failed
    try:
        fn()
        print(f'  PASS  {name}')
        _passed += 1
    except Exception as e:
        print(f'  FAIL  {name}: {e}')
        _failed += 1

def run(instrs, local_count=0, struct_layouts=None, type_sizes=None):
    vm = FluxVM(struct_layouts=struct_layouts, type_sizes=type_sizes)
    return vm, vm.execute(instrs, local_count)

def run_fn(instrs, functions, local_count=0):
    vm = FluxVM()
    for name, body in functions.items():
        vm.register_function(name, body)
    return vm, vm.execute(instrs, local_count)

def i(v):  return Val(TTag.INT,    v)
def u(v):  return Val(TTag.UINT,   v)
def f(v):  return Val(TTag.FLOAT,  v)
def d(v):  return Val(TTag.DOUBLE, v)
def b(v):  return Val(TTag.BOOL,   v)
def by(v): return Val(TTag.BYTE,   v)
def p(op, *args): return Instr(op, list(args))
def push(val):    return Instr(Op.PUSH, [val])


# ---------------------------------------------------------------------------
# Stack ops
# ---------------------------------------------------------------------------

def test_push_pop():
    _, r = run([push(i(7)), p(Op.HALT)])
    assert r.data == 7

def test_dup():
    _, r = run([push(i(5)), p(Op.DUP), p(Op.ADD), p(Op.HALT)])
    assert r.data == 10

def test_swap():
    _, r = run([push(i(1)), push(i(2)), p(Op.SWAP), p(Op.HALT)])
    assert r.data == 1

def test_rot():
    # a=1 b=2 c=3 -> b=2 c=3 a=1; top should be 1
    instrs = [push(i(1)), push(i(2)), push(i(3)), p(Op.ROT), p(Op.HALT)]
    vm, r = run(instrs)
    assert r.data == 1
    assert vm.stack[-2].data == 3
    assert vm.stack[-3].data == 2

def test_over():
    # a=10 b=20 -> a=10 b=20 a=10; top should be 10
    instrs = [push(i(10)), push(i(20)), p(Op.OVER), p(Op.HALT)]
    vm, r = run(instrs)
    assert r.data == 10
    assert vm.stack[-2].data == 20
    assert vm.stack[-3].data == 10

def test_pop():
    # push 1, push 2, POP, HALT -> top is 1
    _, r = run([push(i(1)), push(i(2)), p(Op.POP), p(Op.HALT)])
    assert r.data == 1


# ---------------------------------------------------------------------------
# Arithmetic
# ---------------------------------------------------------------------------

def test_add():
    _, r = run([push(i(10)), push(i(3)), p(Op.ADD), p(Op.HALT)])
    assert r.data == 13

def test_sub():
    _, r = run([push(i(10)), push(i(3)), p(Op.SUB), p(Op.HALT)])
    assert r.data == 7

def test_mul():
    _, r = run([push(i(6)), push(i(7)), p(Op.MUL), p(Op.HALT)])
    assert r.data == 42

def test_div_int():
    _, r = run([push(i(17)), push(i(5)), p(Op.DIV), p(Op.HALT)])
    assert r.data == 3

def test_div_float():
    _, r = run([push(f(10.0)), push(f(4.0)), p(Op.DIV), p(Op.HALT)])
    assert abs(r.data - 2.5) < 1e-6

def test_div_by_zero():
    try:
        run([push(i(1)), push(i(0)), p(Op.DIV), p(Op.HALT)])
        assert False, 'should have raised'
    except VMError:
        pass

def test_mod():
    _, r = run([push(i(17)), push(i(5)), p(Op.MOD), p(Op.HALT)])
    assert r.data == 2

def test_neg():
    _, r = run([push(i(9)), p(Op.NEG), p(Op.HALT)])
    assert r.data == -9

def test_pow():
    _, r = run([push(i(2)), push(i(10)), p(Op.POW), p(Op.HALT)])
    assert r.data == 1024

def test_abs_positive():
    _, r = run([push(i(7)), p(Op.ABS), p(Op.HALT)])
    assert r.data == 7

def test_abs_negative():
    _, r = run([push(i(-9)), p(Op.ABS), p(Op.HALT)])
    assert r.data == 9

def test_min():
    _, r = run([push(i(3)), push(i(7)), p(Op.MIN), p(Op.HALT)])
    assert r.data == 3

def test_max():
    _, r = run([push(i(3)), push(i(7)), p(Op.MAX), p(Op.HALT)])
    assert r.data == 7

def test_clamp_in_range():
    # clamp(5, 1, 10) = 5
    _, r = run([push(i(5)), push(i(1)), push(i(10)), p(Op.CLAMP), p(Op.HALT)])
    assert r.data == 5

def test_clamp_below():
    # clamp(-3, 0, 10) = 0
    _, r = run([push(i(-3)), push(i(0)), push(i(10)), p(Op.CLAMP), p(Op.HALT)])
    assert r.data == 0

def test_clamp_above():
    # clamp(15, 0, 10) = 10
    _, r = run([push(i(15)), push(i(0)), push(i(10)), p(Op.CLAMP), p(Op.HALT)])
    assert r.data == 10


# ---------------------------------------------------------------------------
# Bitwise
# ---------------------------------------------------------------------------

def test_band():
    _, r = run([push(i(0b1100)), push(i(0b1010)), p(Op.BAND), p(Op.HALT)])
    assert r.data == 0b1000

def test_bor():
    _, r = run([push(i(0b1100)), push(i(0b1010)), p(Op.BOR), p(Op.HALT)])
    assert r.data == 0b1110

def test_bxor():
    _, r = run([push(i(0b1100)), push(i(0b1010)), p(Op.BXOR), p(Op.HALT)])
    assert r.data == 0b0110

def test_bnot():
    _, r = run([push(i(0)), p(Op.BNOT), p(Op.HALT)])
    assert r.data == -1

def test_shl():
    _, r = run([push(i(1)), push(i(4)), p(Op.SHL), p(Op.HALT)])
    assert r.data == 16

def test_shr():
    _, r = run([push(i(16)), push(i(2)), p(Op.SHR), p(Op.HALT)])
    assert r.data == 4

def test_rotl():
    # rotl(0b0001, 2, width=8) = 0b0100 = 4
    _, r = run([push(u(0b00000001)), push(u(2)), p(Op.ROTL, 8), p(Op.HALT)])
    assert r.data == 0b00000100

def test_rotl_wraparound():
    # rotl(0b10000000, 1, width=8) = 0b00000001
    _, r = run([push(u(0b10000000)), push(u(1)), p(Op.ROTL, 8), p(Op.HALT)])
    assert r.data == 0b00000001

def test_rotr():
    # rotr(0b10000000, 2, width=8) = 0b00100000
    _, r = run([push(u(0b10000000)), push(u(2)), p(Op.ROTR, 8), p(Op.HALT)])
    assert r.data == 0b00100000

def test_rotr_wraparound():
    # rotr(0b00000001, 1, width=8) = 0b10000000
    _, r = run([push(u(0b00000001)), push(u(1)), p(Op.ROTR, 8), p(Op.HALT)])
    assert r.data == 0b10000000

def test_bitrev():
    # bitrev(0b10110000, width=8) = 0b00001101
    _, r = run([push(u(0b10110000)), p(Op.BITREV, 8), p(Op.HALT)])
    assert r.data == 0b00001101, f'expected 0b00001101 got {r.data:08b}'

def test_bitrev_32():
    # bitrev(0x80000000, width=32) = 0x00000001
    _, r = run([push(u(0x80000000)), p(Op.BITREV, 32), p(Op.HALT)])
    assert r.data == 0x00000001, f'expected 1 got {r.data:#010x}'

def test_popcount():
    _, r = run([push(u(0b10110101)), p(Op.POPCOUNT), p(Op.HALT)])
    assert r.data == 5

def test_popcount_zero():
    _, r = run([push(u(0)), p(Op.POPCOUNT), p(Op.HALT)])
    assert r.data == 0

def test_clz():
    # clz(0b00001000, width=8) = 4
    _, r = run([push(u(0b00001000)), p(Op.CLZ, 8), p(Op.HALT)])
    assert r.data == 4

def test_clz_zero():
    # clz(0, width=8) = 8
    _, r = run([push(u(0)), p(Op.CLZ, 8), p(Op.HALT)])
    assert r.data == 8

def test_ctz():
    # ctz(0b00101000, width=8) = 3
    _, r = run([push(u(0b00101000)), p(Op.CTZ, 8), p(Op.HALT)])
    assert r.data == 3

def test_ctz_zero():
    # ctz(0, width=8) = 8
    _, r = run([push(u(0)), p(Op.CTZ, 8), p(Op.HALT)])
    assert r.data == 8


# ---------------------------------------------------------------------------
# Comparison
# ---------------------------------------------------------------------------

def test_cmp_eq_true():
    _, r = run([push(i(5)), push(i(5)), p(Op.CMP_EQ), p(Op.HALT)])
    assert r.data == 1

def test_cmp_eq_false():
    _, r = run([push(i(5)), push(i(6)), p(Op.CMP_EQ), p(Op.HALT)])
    assert r.data == 0

def test_cmp_ne():
    _, r = run([push(i(3)), push(i(4)), p(Op.CMP_NE), p(Op.HALT)])
    assert r.data == 1

def test_cmp_lt():
    _, r = run([push(i(3)), push(i(4)), p(Op.CMP_LT), p(Op.HALT)])
    assert r.data == 1

def test_cmp_le():
    _, r = run([push(i(4)), push(i(4)), p(Op.CMP_LE), p(Op.HALT)])
    assert r.data == 1

def test_cmp_gt():
    _, r = run([push(i(5)), push(i(3)), p(Op.CMP_GT), p(Op.HALT)])
    assert r.data == 1

def test_cmp_ge():
    _, r = run([push(i(5)), push(i(5)), p(Op.CMP_GE), p(Op.HALT)])
    assert r.data == 1


# ---------------------------------------------------------------------------
# Logic
# ---------------------------------------------------------------------------

def test_and_true():
    _, r = run([push(b(1)), push(b(1)), p(Op.AND), p(Op.HALT)])
    assert r.data == 1

def test_and_false():
    _, r = run([push(b(1)), push(b(0)), p(Op.AND), p(Op.HALT)])
    assert r.data == 0

def test_or_true():
    _, r = run([push(b(0)), push(b(1)), p(Op.OR), p(Op.HALT)])
    assert r.data == 1

def test_or_false():
    _, r = run([push(b(0)), push(b(0)), p(Op.OR), p(Op.HALT)])
    assert r.data == 0

def test_not_true():
    _, r = run([push(b(0)), p(Op.NOT), p(Op.HALT)])
    assert r.data == 1

def test_not_false():
    _, r = run([push(b(1)), p(Op.NOT), p(Op.HALT)])
    assert r.data == 0


# ---------------------------------------------------------------------------
# Control flow
# ---------------------------------------------------------------------------

def test_jmp():
    # JMP over a push, should never see 99
    instrs = [
        push(i(1)),           # 0
        p(Op.JMP, 3),         # 1 - jump to index 3
        push(i(99)),          # 2 - skipped
        p(Op.HALT),           # 3
    ]
    _, r = run(instrs)
    assert r.data == 1

def test_jif_taken():
    instrs = [
        push(i(0)),           # 0 - result placeholder
        push(b(1)),           # 1
        p(Op.JIF, 4),         # 2 - jump to 4
        push(i(99)),          # 3 - skipped
        p(Op.HALT),           # 4
    ]
    _, r = run(instrs)
    assert r.data == 0

def test_jif_not_taken():
    instrs = [
        push(b(0)),           # 0
        p(Op.JIF, 3),         # 1 - not taken
        push(i(42)),          # 2
        p(Op.HALT),           # 3
    ]
    _, r = run(instrs)
    assert r.data == 42

def test_jnf_taken():
    instrs = [
        push(i(0)),           # 0 - placeholder
        push(b(0)),           # 1
        p(Op.JNF, 4),         # 2 - taken
        push(i(99)),          # 3 - skipped
        p(Op.HALT),           # 4
    ]
    _, r = run(instrs)
    assert r.data == 0

def test_jtable_hit():
    # JTABLE with 3 entries; index=1 should jump to addr for case 1
    # layout: 0=push idx, 1=jtable, 2=case0 result, 3=jmp end, 4=case1 result, 5=jmp end, 6=case2 result, 7=halt
    instrs = [
        push(i(1)),                        # 0  index = 1
        p(Op.JTABLE, 7, [2, 4, 6]),        # 1  dispatch
        push(i(100)),                      # 2  case 0
        p(Op.JMP, 7),                      # 3
        push(i(200)),                      # 4  case 1
        p(Op.JMP, 7),                      # 5
        push(i(300)),                      # 6  case 2
        p(Op.HALT),                        # 7
    ]
    _, r = run(instrs)
    assert r.data == 200, f'expected 200 got {r.data}'

def test_jtable_default():
    # Index out of range -> default addr
    instrs = [
        push(i(5)),                        # 0  index = 5 (out of range)
        p(Op.JTABLE, 4, [2, 3]),           # 1  dispatch; default=4
        push(i(10)),                       # 2  case 0
        push(i(20)),                       # 3  case 1
        push(i(99)),                       # 4  default
        p(Op.HALT),                        # 5
    ]
    _, r = run(instrs)
    assert r.data == 99, f'expected 99 got {r.data}'

def test_loop():
    # Sum 1..5 using a loop
    # local 0 = counter, local 1 = sum
    instrs = [
        push(i(1)),           # 0  counter = 1
        p(Op.LOCAL_SET, 0),   # 1
        push(i(0)),           # 2  sum = 0
        p(Op.LOCAL_SET, 1),   # 3
        # loop_start = 4
        p(Op.LOCAL_GET, 0),   # 4  load counter
        push(i(5)),           # 5
        p(Op.CMP_LE),         # 6  counter <= 5
        p(Op.JNF, 17),        # 7  exit if false
        p(Op.LOCAL_GET, 1),   # 8  sum
        p(Op.LOCAL_GET, 0),   # 9  counter
        p(Op.ADD),            # 10 sum + counter
        p(Op.LOCAL_SET, 1),   # 11 sum = sum + counter
        p(Op.LOCAL_GET, 0),   # 12 counter
        push(i(1)),           # 13
        p(Op.ADD),            # 14 counter + 1
        p(Op.LOCAL_SET, 0),   # 15 counter++
        p(Op.JMP, 4),         # 16 back to loop_start
        p(Op.LOCAL_GET, 1),   # 17 push sum
        p(Op.HALT),           # 18
    ]
    _, r = run(instrs, local_count=2)
    assert r.data == 15, f'expected 15 got {r.data}'


# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

def test_locals():
    instrs = [
        push(i(100)),
        p(Op.LOCAL_SET, 0),
        push(i(200)),
        p(Op.LOCAL_SET, 1),
        p(Op.LOCAL_GET, 0),
        p(Op.LOCAL_GET, 1),
        p(Op.ADD),
        p(Op.HALT),
    ]
    _, r = run(instrs, local_count=2)
    assert r.data == 300

def test_local_deref():
    # Push PTR(slot=0), LOCAL_DEREF should yield locals[0]
    instrs = [
        push(i(42)),
        p(Op.LOCAL_SET, 0),
        push(Val(TTag.PTR, 0)),   # PTR(slot=0)
        p(Op.LOCAL_DEREF),
        p(Op.HALT),
    ]
    _, r = run(instrs, local_count=1)
    assert r.data == 42

def test_local_deref_set():
    # Push PTR(slot=1), value 77; LOCAL_DEREF_SET stores 77 into locals[1]
    instrs = [
        push(i(0)),
        p(Op.LOCAL_SET, 1),       # locals[1] = 0
        push(Val(TTag.PTR, 1)),   # PTR(slot=1)
        push(i(77)),
        p(Op.LOCAL_DEREF_SET),
        p(Op.LOCAL_GET, 1),
        p(Op.HALT),
    ]
    _, r = run(instrs, local_count=2)
    assert r.data == 77


# ---------------------------------------------------------------------------
# Function call / return
# ---------------------------------------------------------------------------

def test_call_ret():
    # double(x) = x * 2
    double_body = [
        p(Op.LOCAL_GET, 0),
        push(i(2)),
        p(Op.MUL),
        p(Op.RET),
    ]
    instrs = [
        push(i(21)),
        p(Op.CALL, 'double', 1),
        p(Op.HALT),
    ]
    _, r = run_fn(instrs, {'double': double_body})
    assert r.data == 42

def test_call_recursive():
    # factorial(n): if n<=1 return 1 else return n * factorial(n-1)
    # local 0 = n
    fact_body = [
        p(Op.LOCAL_GET, 0),   # 0
        push(i(1)),           # 1
        p(Op.CMP_LE),         # 2
        p(Op.JNF, 6),         # 3  if n > 1 jump to 6
        push(i(1)),           # 4  base case
        p(Op.RET),            # 5
        p(Op.LOCAL_GET, 0),   # 6  n
        p(Op.LOCAL_GET, 0),   # 7  n
        push(i(1)),           # 8
        p(Op.SUB),            # 9  n-1
        p(Op.CALL, 'fact', 1),# 10 fact(n-1)
        p(Op.MUL),            # 11 n * fact(n-1)
        p(Op.RET),            # 12
    ]
    instrs = [
        push(i(6)),
        p(Op.CALL, 'fact', 1),
        p(Op.HALT),
    ]
    _, r = run_fn(instrs, {'fact': fact_body})
    assert r.data == 720, f'expected 720 got {r.data}'

def test_call_ptr():
    # CALL_PTR: push argument, then function name as BYTES, then CALL_PTR
    double_body = [
        p(Op.LOCAL_GET, 0),
        push(i(2)),
        p(Op.MUL),
        p(Op.RET),
    ]
    instrs = [
        push(i(9)),                          # argument
        push(Val(TTag.BYTES, b'double')),    # function name (popped first by CALL_PTR)
        p(Op.CALL_PTR, 1),
        p(Op.HALT),
    ]
    _, r = run_fn(instrs, {'double': double_body})
    assert r.data == 18, f'expected 18 got {r.data}'

def test_tail_self():
    # TAIL_SELF: iterative sum via tail-call; count_sum(n, acc) -> sum 1..5
    # local 0 = n, local 1 = acc
    # if n==0 return acc; else tail_self(n-1, acc+n)
    count_body = [
        p(Op.LOCAL_GET, 0),    # 0  n
        push(i(0)),            # 1
        p(Op.CMP_EQ),          # 2  n == 0
        p(Op.JNF, 6),          # 3  if n != 0, jump to 6
        p(Op.LOCAL_GET, 1),    # 4  return acc
        p(Op.RET),             # 5
        p(Op.LOCAL_GET, 0),    # 6  n
        push(i(1)),            # 7
        p(Op.SUB),             # 8  n - 1  (new arg0)
        p(Op.LOCAL_GET, 1),    # 9  acc
        p(Op.LOCAL_GET, 0),    # 10 n
        p(Op.ADD),             # 11 acc + n  (new arg1)
        p(Op.TAIL_SELF, 2),    # 12 reuse frame with new (n-1, acc+n)
    ]
    instrs = [
        push(i(5)),
        push(i(0)),
        p(Op.CALL, 'count_sum', 2),
        p(Op.HALT),
    ]
    _, r = run_fn(instrs, {'count_sum': count_body})
    assert r.data == 15, f'expected 15 got {r.data}'


# ---------------------------------------------------------------------------
# Memory
# ---------------------------------------------------------------------------

def test_alloc_free():
    instrs = [
        push(i(16)),
        p(Op.ALLOC),
        p(Op.FREE),
        push(i(0)),
        p(Op.HALT),
    ]
    _, r = run(instrs)
    assert r.data == 0

def test_store_load_int():
    instrs = [
        push(i(4)),
        p(Op.ALLOC),
        p(Op.DUP),
        push(i(1234)),
        p(Op.STORE, TTag.INT, 4),
        p(Op.LOAD, TTag.INT, 4),
        p(Op.HALT),
    ]
    _, r = run(instrs)
    assert r.data == 1234

def test_store_load_float():
    instrs = [
        push(i(4)),
        p(Op.ALLOC),
        p(Op.DUP),
        push(f(3.14)),
        p(Op.STORE, TTag.FLOAT, 4),
        p(Op.LOAD, TTag.FLOAT, 4),
        p(Op.HALT),
    ]
    _, r = run(instrs)
    assert abs(r.data - 3.14) < 1e-5

def test_offset():
    # Allocate 8 bytes, write two ints at offset 0 and 4, read back second
    instrs = [
        push(i(8)),
        p(Op.ALLOC),
        p(Op.LOCAL_SET, 0),
        # store 11 at offset 0
        p(Op.LOCAL_GET, 0),
        push(i(11)),
        p(Op.STORE, TTag.INT, 4),
        # store 22 at offset 4
        p(Op.LOCAL_GET, 0),
        push(i(4)),
        p(Op.OFFSET),
        push(i(22)),
        p(Op.STORE, TTag.INT, 4),
        # load from offset 4
        p(Op.LOCAL_GET, 0),
        push(i(4)),
        p(Op.OFFSET),
        p(Op.LOAD, TTag.INT, 4),
        p(Op.HALT),
    ]
    _, r = run(instrs, local_count=1)
    assert r.data == 22

def test_oob_access():
    vm = FluxVM(heap_size=64)
    instrs = [
        push(i(8)),
        p(Op.ALLOC),
        push(i(1000)),
        p(Op.OFFSET),
        p(Op.LOAD, TTag.INT, 4),
        p(Op.HALT),
    ]
    try:
        vm.execute(instrs)
        assert False, 'should have raised'
    except VMError:
        pass


# ---------------------------------------------------------------------------
# Structs
# ---------------------------------------------------------------------------

_point_layout = {
    'Point': StructLayout('Point', [
        ('x', TTag.INT, 0, 4),
        ('y', TTag.INT, 4, 4),
    ], total_size=8)
}

def test_struct_new():
    instrs = [
        p(Op.STRUCT_NEW, 'Point'),
        p(Op.HALT),
    ]
    _, r = run(instrs, struct_layouts=_point_layout)
    assert r.tag == TTag.STRUCT
    assert r.data == 'Point'

def test_field_set_get():
    # STRUCT_STORE returns updated struct; store back with LOCAL_SET
    instrs = [
        p(Op.STRUCT_NEW, 'Point'),
        p(Op.LOCAL_SET, 0),
        # s.x = 7
        p(Op.LOCAL_GET, 0),
        push(i(7)),
        p(Op.STRUCT_STORE, 'x'),
        p(Op.LOCAL_SET, 0),
        # s.y = 13
        p(Op.LOCAL_GET, 0),
        push(i(13)),
        p(Op.STRUCT_STORE, 'y'),
        p(Op.LOCAL_SET, 0),
        # s.x + s.y
        p(Op.LOCAL_GET, 0),
        p(Op.STRUCT_LOAD, 'x'),
        p(Op.LOCAL_GET, 0),
        p(Op.STRUCT_LOAD, 'y'),
        p(Op.ADD),
        p(Op.HALT),
    ]
    _, r = run(instrs, local_count=1, struct_layouts=_point_layout)
    assert r.data == 20

def test_field_not_found():
    instrs = [
        p(Op.STRUCT_NEW, 'Point'),
        p(Op.STRUCT_LOAD, 'z'),
        p(Op.HALT),
    ]
    try:
        run(instrs, struct_layouts=_point_layout)
        assert False, 'should have raised'
    except VMError:
        pass


# ---------------------------------------------------------------------------
# Arrays
# ---------------------------------------------------------------------------

def test_array_new():
    instrs = [
        p(Op.ARRAY_NEW, 'int', 8),
        p(Op.HALT),
    ]
    _, r = run(instrs)
    assert r.tag == TTag.ARRAY
    assert r.meta.get('count') == 8

def test_index_set_get():
    instrs = [
        p(Op.ARRAY_NEW, 'int', 4),
        p(Op.LOCAL_SET, 0),
        # arr[2] = 99  -> ARRAY_STORE returns updated array; write back
        p(Op.LOCAL_GET, 0),
        push(i(2)),
        push(i(99)),
        p(Op.ARRAY_STORE),
        p(Op.LOCAL_SET, 0),
        # arr[2]
        p(Op.LOCAL_GET, 0),
        push(i(2)),
        p(Op.ARRAY_LOAD),
        p(Op.HALT),
    ]
    _, r = run(instrs, local_count=1)
    assert r.data == 99

def test_array_len():
    instrs = [
        p(Op.ARRAY_NEW, 'int', 7),
        p(Op.ARRAY_LEN),
        p(Op.HALT),
    ]
    _, r = run(instrs)
    assert r.data == 7, f'expected 7 got {r.data}'


# ---------------------------------------------------------------------------
# Heap free-list
# ---------------------------------------------------------------------------

def test_heap_free_list_reuse():
    # Alloc a block, free it, alloc same size again; pointer should be reused
    vm = FluxVM()
    instrs = [
        push(i(16)),
        p(Op.ALLOC),
        p(Op.LOCAL_SET, 0),
        p(Op.LOCAL_GET, 0),
        p(Op.FREE),
        push(i(16)),
        p(Op.ALLOC),
        p(Op.HALT),
    ]
    _, r = run(instrs, local_count=1)
    # The VM heap free-list must have supplied the previously freed block
    assert r.tag == TTag.PTR


# ---------------------------------------------------------------------------
# last_locals
# ---------------------------------------------------------------------------

def test_last_locals_after_halt():
    # HALT should snapshot the top-level frame's locals into vm.last_locals
    vm = FluxVM()
    instrs = [
        push(i(55)),
        p(Op.LOCAL_SET, 0),
        push(i(66)),
        p(Op.LOCAL_SET, 1),
        push(i(0)),
        p(Op.HALT),
    ]
    vm.execute(instrs, local_count=2)
    assert len(vm.last_locals) == 2
    assert vm.last_locals[0].data == 55
    assert vm.last_locals[1].data == 66


# ---------------------------------------------------------------------------
# Type introspection
# ---------------------------------------------------------------------------

def test_sizeof_int():
    _, r = run([p(Op.SIZEOF, 'int'), p(Op.HALT)])
    assert r.data == 32

def test_sizeof_double():
    _, r = run([p(Op.SIZEOF, 'double'), p(Op.HALT)])
    assert r.data == 64

def test_sizeof_struct():
    _, r = run([p(Op.SIZEOF, 'Point'), p(Op.HALT)], struct_layouts=_point_layout)
    assert r.data == 64

def test_typeof():
    _, r = run([push(f(1.0)), p(Op.TYPEOF), p(Op.HALT)])
    assert r.data == b'float'

def test_alignof_int():
    _, r = run([p(Op.ALIGNOF, 'int'), p(Op.HALT)])
    assert r.data == 4

def test_alignof_struct():
    _, r = run([p(Op.ALIGNOF, 'Point'), p(Op.HALT)], struct_layouts=_point_layout)
    assert r.data == 4

def test_endianof_little():
    _, r = run([p(Op.ENDIANOF, 'int'), p(Op.HALT)])
    assert r.data == b'little'

def test_endianof_big():
    _, r = run([p(Op.ENDIANOF, 'be32'), p(Op.HALT)])
    assert r.data == b'big'

def test_endianof_struct():
    layout = {'Packet': StructLayout('Packet', [], total_size=4, endian='big')}
    _, r = run([p(Op.ENDIANOF, 'Packet'), p(Op.HALT)], struct_layouts=layout)
    assert r.data == b'big'


# ---------------------------------------------------------------------------
# IO
# ---------------------------------------------------------------------------

def test_io_write_read():
    with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tf:
        path = tf.name
    try:
        vm = FluxVM()
        # Write 'hello' to file
        msg = b'hello'
        ptr = vm.heap.alloc(len(msg) + 1)
        vm.heap.write(ptr, msg + b'\x00')
        path_ptr = vm.heap.alloc(len(path.encode()) + 1)
        vm.heap.write(path_ptr, path.encode() + b'\x00')
        mode_ptr = vm.heap.alloc(3)
        vm.heap.write(mode_ptr, b'wb\x00')
        write_instrs = [
            push(Val(TTag.PTR, path_ptr)),
            push(Val(TTag.PTR, mode_ptr)),
            p(Op.IO_OPEN),
            p(Op.LOCAL_SET, 0),
            p(Op.LOCAL_GET, 0),
            push(Val(TTag.PTR, ptr)),
            push(i(len(msg))),
            p(Op.IO_WRITE),
            p(Op.LOCAL_GET, 0),
            p(Op.IO_CLOSE),
            push(i(0)),
            p(Op.HALT),
        ]
        vm.execute(write_instrs, local_count=1)
        # Read back - use string vals so VM allocates them on its own heap
        vm2 = FluxVM()
        read_instrs = [
            push(Val(TTag.BYTES, path.encode())),
            push(Val(TTag.BYTES, b'rb')),
            p(Op.IO_OPEN),
            p(Op.LOCAL_SET, 0),
            p(Op.LOCAL_GET, 0),
            push(i(len(msg))),
            p(Op.IO_READ),
            p(Op.LOCAL_SET, 1),
            p(Op.LOCAL_GET, 0),
            p(Op.IO_CLOSE),
            push(i(0)),
            p(Op.HALT),
        ]
        vm2.execute(read_instrs, local_count=2)
        # Verify file contents
        with open(path, 'rb') as fh:
            assert fh.read() == msg
    finally:
        os.unlink(path)

def test_io_invalid_handle():
    instrs = [
        push(Val(TTag.FILE, 999)),
        push(i(4)),
        p(Op.IO_READ),
        p(Op.HALT),
    ]
    try:
        run(instrs)
        assert False, 'should have raised'
    except VMError:
        pass


# ---------------------------------------------------------------------------
# FFI
# ---------------------------------------------------------------------------

def test_ffi_load_sym_call():
    import ctypes.util
    libm = ctypes.util.find_library('m')
    if libm is None:
        # Try common paths
        for candidate in ('libm.so.6', 'libm.so', 'msvcrt.dll'):
            try:
                ctypes.CDLL(candidate)
                libm = candidate
                break
            except OSError:
                pass
    if libm is None:
        print('    (skipped - libm not found)')
        return
    vm = FluxVM()
    # abs(-7) via FFI
    instrs = [
        p(Op.FFI_LOAD, libm),
        p(Op.FFI_SYM, 'abs'),
        push(i(-7)),
        p(Op.FFI_CALL, 1, TTag.INT),
        p(Op.HALT),
    ]
    _, r = vm, vm.execute(instrs)
    assert r.data == 7, f'expected 7 got {r.data}'

def test_ffi_free():
    import ctypes.util
    libm = ctypes.util.find_library('m')
    if libm is None:
        print('    (skipped - libm not found)')
        return
    vm = FluxVM()
    instrs = [
        p(Op.FFI_LOAD, libm),
        p(Op.FFI_FREE),
        push(i(0)),
        p(Op.HALT),
    ]
    _, r = vm, vm.execute(instrs)
    assert libm not in vm._ffi_libs

def test_ffi_bad_lib():
    instrs = [
        p(Op.FFI_LOAD, 'nonexistent_library_xyz.so'),
        p(Op.HALT),
    ]
    try:
        run(instrs)
        assert False, 'should have raised'
    except VMError:
        pass


# ---------------------------------------------------------------------------
# Boundary crossing (EMIT_*)
# ---------------------------------------------------------------------------

def test_emit_const():
    vm = FluxVM()
    instrs = [
        push(i(255)),
        p(Op.EMIT_CONST),
        push(i(0)),
        p(Op.HALT),
    ]
    vm.execute(instrs)
    assert len(vm.emit_results) == 1
    kind, val = vm.emit_results[0]
    assert kind == 'const'
    assert val.data == 255

def test_emit_global():
    vm = FluxVM()
    ptr = vm.heap.alloc(4)
    vm.heap.write(ptr, b'\xDE\xAD\xBE\xEF')
    instrs = [
        push(Val(TTag.PTR, ptr)),
        p(Op.EMIT_GLOBAL, 4),
        push(i(0)),
        p(Op.HALT),
    ]
    vm.execute(instrs)
    assert len(vm.emit_results) == 1
    kind, data, meta = vm.emit_results[0]
    assert kind == 'global'
    assert data == b'\xDE\xAD\xBE\xEF'

def test_emit_type():
    instrs = [
        push(Val(TTag.BYTES, b'int')),
        p(Op.EMIT_TYPE),
        push(i(0)),
        p(Op.HALT),
    ]
    vm = FluxVM()
    vm.execute(instrs)
    assert len(vm.emit_results) == 1
    kind, val = vm.emit_results[0]
    assert kind == 'type'
    assert val.data == b'int'


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

def test_stack_underflow():
    try:
        run([p(Op.ADD), p(Op.HALT)])
        assert False, 'should have raised'
    except (VMError, IndexError):
        pass

def test_unknown_function():
    try:
        run([p(Op.CALL, 'nope', 0), p(Op.HALT)])
        assert False, 'should have raised'
    except VMError:
        pass

def test_unknown_struct():
    try:
        run([p(Op.STRUCT_NEW, 'Ghost'), p(Op.HALT)])
        assert False, 'should have raised'
    except VMError:
        pass

def test_free_invalid_ptr():
    try:
        run([push(Val(TTag.PTR, 9999)), p(Op.FREE), push(i(0)), p(Op.HALT)])
        assert False, 'should have raised'
    except VMError:
        pass

def test_multiple_emit_consts():
    vm = FluxVM()
    instrs = [
        push(i(1)), p(Op.EMIT_CONST),
        push(i(2)), p(Op.EMIT_CONST),
        push(i(3)), p(Op.EMIT_CONST),
        push(i(0)), p(Op.HALT),
    ]
    vm.execute(instrs)
    assert len(vm.emit_results) == 3
    assert [v.data for _, v in vm.emit_results] == [1, 2, 3]

def test_emitflux_plain():
    # Simple substitution: variable i at slot 0 holds value 7
    vm = FluxVM()
    instrs = [
        push(i(7)),
        p(Op.LOCAL_SET, 0),
        p(Op.EMITFLUX, 'global int VAR = i ;', [('i', 0)]),
        push(i(0)),
        p(Op.HALT),
    ]
    vm.execute(instrs, local_count=1)
    assert len(vm.emit_results) == 1
    kind, text = vm.emit_results[0]
    assert kind == 'flux'
    assert '7' in text, f'expected 7 in substituted text, got {text!r}'
    assert 'i' not in text.replace('int', ''), f'variable name should be substituted, got {text!r}'

def test_emitflux_fstring_codify():
    # ~$f"VAR_{i}" substitution where i=2 should yield VAR_2
    vm = FluxVM()
    instrs = [
        push(i(2)),
        p(Op.LOCAL_SET, 0),
        p(Op.EMITFLUX, 'global int ~$f"VAR_{i}" = i ;', [('i', 0)]),
        push(i(0)),
        p(Op.HALT),
    ]
    vm.execute(instrs, local_count=1)
    assert len(vm.emit_results) == 1
    kind, text = vm.emit_results[0]
    assert kind == 'flux'
    assert 'VAR_2' in text, f'expected VAR_2 in text, got {text!r}'
    assert '2' in text, f'expected value 2 in text, got {text!r}'

def test_emitflux_loop():
    # Simulate the plan's canonical example: emit 4 globals VAR_0..VAR_3
    vm = FluxVM()
    # Loop: i goes 0..3; each iteration emits one EMITFLUX
    # local 0 = i
    instrs = [
        push(i(0)),
        p(Op.LOCAL_SET, 0),            # i = 0
        # loop_start = 2
        p(Op.LOCAL_GET, 0),            # 2
        push(i(4)),                    # 3
        p(Op.CMP_LT),                  # 4   i < 4
        p(Op.JNF, 9),                  # 5   exit if false
        p(Op.EMITFLUX, 'global int ~$f"VAR_{i}" = i ;', [('i', 0)]),  # 6
        p(Op.LOCAL_GET, 0),            # 7
        push(i(1)),                    # 8  (these are at indices 8,9 -- wait, need recount)
        p(Op.ADD),                     # 9
        p(Op.LOCAL_SET, 0),            # 10  i++
        p(Op.JMP, 2),                  # 11  back to loop_start
        push(i(0)),                    # 12
        p(Op.HALT),                    # 13
    ]
    # Fix the JNF target to point past the loop body
    # Recount: indices 0..13, loop body is 6..11, after loop is 12
    instrs = [
        push(i(0)),                    # 0
        p(Op.LOCAL_SET, 0),            # 1
        p(Op.LOCAL_GET, 0),            # 2
        push(i(4)),                    # 3
        p(Op.CMP_LT),                  # 4
        p(Op.JNF, 12),                 # 5  exit to 12
        p(Op.EMITFLUX, 'global int ~$f"VAR_{i}" = i ;', [('i', 0)]),  # 6
        p(Op.LOCAL_GET, 0),            # 7
        push(i(1)),                    # 8
        p(Op.ADD),                     # 9
        p(Op.LOCAL_SET, 0),            # 10
        p(Op.JMP, 2),                  # 11
        push(i(0)),                    # 12
        p(Op.HALT),                    # 13
    ]
    vm.execute(instrs, local_count=1)
    assert len(vm.emit_results) == 4, f'expected 4 emissions, got {len(vm.emit_results)}'
    for idx, (kind, text) in enumerate(vm.emit_results):
        assert kind == 'flux'
        assert f'VAR_{idx}' in text, f'expected VAR_{idx} in emission {idx}, got {text!r}'
        assert str(idx) in text, f'expected value {idx} in emission {idx}, got {text!r}'


# ---------------------------------------------------------------------------
# compiler.io
# ---------------------------------------------------------------------------

def test_compiler_print():
    import io as _io
    old_stdout = sys.stdout
    sys.stdout = _io.StringIO()
    try:
        vm = FluxVM()
        instrs = [
            push(Val(TTag.BYTES, b'hello comptime')),
            p(Op.COMPILER_PRINT),
            push(i(0)),
            p(Op.HALT),
        ]
        vm.execute(instrs)
        output = sys.stdout.getvalue()
    finally:
        sys.stdout = old_stdout
    assert output == 'hello comptime', f'got {output!r}'

def test_compiler_input():
    import io as _io
    old_stdin = sys.stdin
    sys.stdin = _io.StringIO('test input\n')
    try:
        vm = FluxVM()
        instrs = [
            p(Op.COMPILER_INPUT),
            p(Op.HALT),
        ]
        result = vm.execute(instrs)
    finally:
        sys.stdin = old_stdin
    assert result.tag == TTag.BYTES
    # Read back the string value
    text = vm._read_vm_string(result)
    assert text == 'test input\n', f'got {text!r}'

def test_compiler_readfile():
    with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tf:
        tf.write(b'flux comptime')
        path = tf.name
    try:
        vm = FluxVM()
        instrs = [
            push(Val(TTag.BYTES, path.encode())),
            p(Op.COMPILER_READFILE),
            p(Op.HALT),
        ]
        result = vm.execute(instrs)
        text = vm._read_vm_string(result)
        assert text == 'flux comptime', f'got {text!r}'
    finally:
        os.unlink(path)

def test_compiler_writefile_binary():
    with tempfile.NamedTemporaryFile(delete=False, suffix='.bin') as tf:
        path = tf.name
    try:
        vm = FluxVM()
        instrs = [
            push(Val(TTag.BYTES, path.encode())),
            push(Val(TTag.BYTES, b'\xDE\xAD\xBE\xEF')),
            push(Val(TTag.BYTES, b'w')),
            p(Op.COMPILER_WRITEFILE),
            push(i(0)),
            p(Op.HALT),
        ]
        vm.execute(instrs)
        with open(path, 'rb') as fh:
            assert fh.read() == b'\xDE\xAD\xBE\xEF'
    finally:
        os.unlink(path)

def test_compiler_writefile_text():
    with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tf:
        path = tf.name
    try:
        vm = FluxVM()
        instrs = [
            push(Val(TTag.BYTES, path.encode())),
            push(Val(TTag.BYTES, b'hello text')),
            push(Val(TTag.BYTES, b'wt')),
            p(Op.COMPILER_WRITEFILE),
            push(i(0)),
            p(Op.HALT),
        ]
        vm.execute(instrs)
        with open(path, 'r') as fh:
            assert fh.read() == 'hello text'
    finally:
        os.unlink(path)

def test_compiler_writefile_append():
    with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tf:
        tf.write(b'first ')
        path = tf.name
    try:
        vm = FluxVM()
        instrs = [
            push(Val(TTag.BYTES, path.encode())),
            push(Val(TTag.BYTES, b'second')),
            push(Val(TTag.BYTES, b'a')),
            p(Op.COMPILER_WRITEFILE),
            push(i(0)),
            p(Op.HALT),
        ]
        vm.execute(instrs)
        with open(path, 'rb') as fh:
            assert fh.read() == b'first second'
    finally:
        os.unlink(path)

def test_compiler_readfile_missing():
    instrs = [
        push(Val(TTag.BYTES, b'/nonexistent/path/file.txt')),
        p(Op.COMPILER_READFILE),
        p(Op.HALT),
    ]
    try:
        run(instrs)
        assert False, 'should have raised'
    except VMError:
        pass


# ---------------------------------------------------------------------------
# String ops
# ---------------------------------------------------------------------------

def test_str_len():
    _, r = run([push(Val(TTag.BYTES, b'hello')), p(Op.STR_LEN), p(Op.HALT)])
    assert r.data == 5

def test_str_len_empty():
    _, r = run([push(Val(TTag.BYTES, b'')), p(Op.STR_LEN), p(Op.HALT)])
    assert r.data == 0

def test_str_cat():
    vm, r = run([
        push(Val(TTag.BYTES, b'foo')),
        push(Val(TTag.BYTES, b'bar')),
        p(Op.STR_CAT),
        p(Op.HALT),
    ])
    text = vm._read_vm_string(r)
    assert text == 'foobar', f'got {text!r}'

def test_str_slice():
    vm, r = run([
        push(Val(TTag.BYTES, b'hello world')),
        push(i(6)),
        push(i(5)),
        p(Op.STR_SLICE),
        p(Op.HALT),
    ])
    text = vm._read_vm_string(r)
    assert text == 'world', f'got {text!r}'

def test_str_eq_true():
    _, r = run([
        push(Val(TTag.BYTES, b'flux')),
        push(Val(TTag.BYTES, b'flux')),
        p(Op.STR_EQ),
        p(Op.HALT),
    ])
    assert r.data == 1

def test_str_eq_false():
    _, r = run([
        push(Val(TTag.BYTES, b'flux')),
        push(Val(TTag.BYTES, b'rust')),
        p(Op.STR_EQ),
        p(Op.HALT),
    ])
    assert r.data == 0

def test_str_find_found():
    _, r = run([
        push(Val(TTag.BYTES, b'hello world')),
        push(Val(TTag.BYTES, b'world')),
        p(Op.STR_FIND),
        p(Op.HALT),
    ])
    assert r.data == 6

def test_str_find_not_found():
    _, r = run([
        push(Val(TTag.BYTES, b'hello world')),
        push(Val(TTag.BYTES, b'xyz')),
        p(Op.STR_FIND),
        p(Op.HALT),
    ])
    assert r.data == -1

def test_int_to_str():
    vm, r = run([push(i(42)), p(Op.INT_TO_STR), p(Op.HALT)])
    text = vm._read_vm_string(r)
    assert text == '42', f'got {text!r}'

def test_int_to_str_negative():
    vm, r = run([push(i(-7)), p(Op.INT_TO_STR), p(Op.HALT)])
    text = vm._read_vm_string(r)
    assert text == '-7', f'got {text!r}'

def test_str_to_int():
    _, r = run([push(Val(TTag.BYTES, b'1234')), p(Op.STR_TO_INT), p(Op.HALT)])
    assert r.data == 1234

def test_str_to_int_hex():
    _, r = run([push(Val(TTag.BYTES, b'0xFF')), p(Op.STR_TO_INT), p(Op.HALT)])
    assert r.data == 255

def test_str_to_int_invalid():
    try:
        run([push(Val(TTag.BYTES, b'notanumber')), p(Op.STR_TO_INT), p(Op.HALT)])
        assert False, 'should have raised'
    except VMError:
        pass


# ---------------------------------------------------------------------------
# Type conversion
# ---------------------------------------------------------------------------

def test_cast_int_to_float():
    _, r = run([push(i(7)), p(Op.CAST, TTag.FLOAT), p(Op.HALT)])
    assert r.tag == TTag.FLOAT
    assert abs(r.data - 7.0) < 1e-6

def test_cast_float_to_int():
    _, r = run([push(f(3.9)), p(Op.CAST, TTag.INT), p(Op.HALT)])
    assert r.tag == TTag.INT
    assert r.data == 3

def test_cast_int_to_bool():
    _, r = run([push(i(5)), p(Op.CAST, TTag.BOOL), p(Op.HALT)])
    assert r.tag == TTag.BOOL
    assert r.data == 1

def test_cast_zero_to_bool():
    _, r = run([push(i(0)), p(Op.CAST, TTag.BOOL), p(Op.HALT)])
    assert r.tag == TTag.BOOL
    assert r.data == 0

def test_bitcast_float_to_int():
    import struct
    bits = struct.unpack('<I', struct.pack('<f', 1.0))[0]
    _, r = run([push(f(1.0)), p(Op.BITCAST, TTag.UINT), p(Op.HALT)])
    assert r.tag == TTag.UINT
    assert r.data == bits, f'expected {bits:#010x} got {r.data:#010x}'

def test_bitcast_int_to_float():
    import struct
    bits = struct.unpack('<I', struct.pack('<f', 1.0))[0]
    _, r = run([push(u(bits)), p(Op.BITCAST, TTag.FLOAT), p(Op.HALT)])
    assert r.tag == TTag.FLOAT
    assert abs(r.data - 1.0) < 1e-6

def test_cast_int_to_long():
    _, r = run([push(i(999)), p(Op.CAST, TTag.LONG), p(Op.HALT)])
    assert r.tag == TTag.LONG
    assert r.data == 999

def test_cast_int_to_ulong():
    _, r = run([push(i(1)), p(Op.CAST, TTag.ULONG), p(Op.HALT)])
    assert r.tag == TTag.ULONG
    assert r.data == 1

def test_cast_int_to_double():
    _, r = run([push(i(3)), p(Op.CAST, TTag.DOUBLE), p(Op.HALT)])
    assert r.tag == TTag.DOUBLE
    assert abs(r.data - 3.0) < 1e-9

def test_cast_int_to_char():
    _, r = run([push(i(65)), p(Op.CAST, TTag.CHAR), p(Op.HALT)])
    assert r.tag == TTag.CHAR
    assert r.data == 65

def test_int_to_str_char():
    # INT_TO_STR on a CHAR value should produce the character string
    vm, r = run([push(Val(TTag.CHAR, ord('A'))), p(Op.INT_TO_STR), p(Op.HALT)])
    text = vm._read_vm_string(r)
    assert text == 'A', f'got {text!r}'



class _NullCG:
    def __init__(self, **kw): self.compiled_functions = {}; self._struct_layouts = {}
    def _visit_stmt(self, n): pass

def test_compiler_import_stdlib():
    vm = FluxVM()
    vm._preprocess_import = lambda path, kind: ''
    vm._codegen_class = _NullCG
    instrs = [push(Val(TTag.BYTES, b'math.fx')), p(Op.COMPILER_IMPORT_STDLIB), p(Op.HALT)]
    vm.execute(instrs)
    assert vm.emit_results[-1][0] == 'import_stdlib'
    assert vm.emit_results[-1][2] == 'math.fx'

def test_compiler_import_local():
    vm = FluxVM()
    vm._preprocess_import = lambda path, kind: ''
    vm._codegen_class = _NullCG
    instrs = [push(Val(TTag.BYTES, b'./utils.fx')), p(Op.COMPILER_IMPORT_LOCAL), p(Op.HALT)]
    vm.execute(instrs)
    assert vm.emit_results[-1][0] == 'import_local'
    assert vm.emit_results[-1][2] == './utils.fx'

def test_compiler_fpm_package():
    vm = FluxVM()
    vm._preprocess_import = lambda path, kind: ''
    vm._codegen_class = _NullCG
    instrs = [push(Val(TTag.BYTES, b'flux/json')), p(Op.COMPILER_FPM_PACKAGE), p(Op.HALT)]
    vm.execute(instrs)
    assert vm.emit_results[-1][0] == 'import_package'
    assert vm.emit_results[-1][2] == 'flux/json'

# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------

def test_assert_pass():
    instrs = [
        push(b(1)),
        push(Val(TTag.BYTES, b'should not fire')),
        p(Op.ASSERT),
        push(i(1)),
        p(Op.HALT),
    ]
    _, r = run(instrs)
    assert r.data == 1

def test_assert_fail():
    instrs = [
        push(b(0)),
        push(Val(TTag.BYTES, b'invariant violated')),
        p(Op.ASSERT),
        push(i(0)),
        p(Op.HALT),
    ]
    try:
        run(instrs)
        assert False, 'should have raised'
    except VMError as e:
        assert 'invariant violated' in str(e)

def test_warn():
    import io as _io
    old_stderr = sys.stderr
    sys.stderr = _io.StringIO()
    try:
        run([
            push(Val(TTag.BYTES, b'test warning message')),
            p(Op.WARN),
            push(i(0)),
            p(Op.HALT),
        ])
        output = sys.stderr.getvalue()
    finally:
        sys.stderr = old_stderr
    assert 'test warning message' in output

def test_panic():
    instrs = [
        push(Val(TTag.BYTES, b'fatal comptime error')),
        p(Op.PANIC),
        push(i(0)),
        p(Op.HALT),
    ]
    try:
        run(instrs)
        assert False, 'should have raised'
    except VMError as e:
        assert 'fatal comptime error' in str(e)


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def main():
    sections = [
        ('Stack', [
            ('PUSH / HALT',        test_push_pop),
            ('DUP',                test_dup),
            ('SWAP',               test_swap),
            ('ROT',                test_rot),
            ('OVER',               test_over),
            ('POP',                test_pop),
        ]),
        ('Arithmetic', [
            ('ADD',                test_add),
            ('SUB',                test_sub),
            ('MUL',                test_mul),
            ('DIV int',            test_div_int),
            ('DIV float',          test_div_float),
            ('DIV by zero',        test_div_by_zero),
            ('MOD',                test_mod),
            ('NEG',                test_neg),
            ('POW',                test_pow),
            ('ABS positive',       test_abs_positive),
            ('ABS negative',       test_abs_negative),
            ('MIN',                test_min),
            ('MAX',                test_max),
            ('CLAMP in range',     test_clamp_in_range),
            ('CLAMP below',        test_clamp_below),
            ('CLAMP above',        test_clamp_above),
        ]),
        ('Bitwise', [
            ('BAND',               test_band),
            ('BOR',                test_bor),
            ('BXOR',               test_bxor),
            ('BNOT',               test_bnot),
            ('SHL',                test_shl),
            ('SHR',                test_shr),
            ('ROTL',               test_rotl),
            ('ROTL wraparound',    test_rotl_wraparound),
            ('ROTR',               test_rotr),
            ('ROTR wraparound',    test_rotr_wraparound),
            ('BITREV 8-bit',       test_bitrev),
            ('BITREV 32-bit',      test_bitrev_32),
            ('POPCOUNT',           test_popcount),
            ('POPCOUNT zero',      test_popcount_zero),
            ('CLZ',                test_clz),
            ('CLZ zero',           test_clz_zero),
            ('CTZ',                test_ctz),
            ('CTZ zero',           test_ctz_zero),
        ]),
        ('Comparison', [
            ('CMP_EQ true',        test_cmp_eq_true),
            ('CMP_EQ false',       test_cmp_eq_false),
            ('CMP_NE',             test_cmp_ne),
            ('CMP_LT',             test_cmp_lt),
            ('CMP_LE',             test_cmp_le),
            ('CMP_GT',             test_cmp_gt),
            ('CMP_GE',             test_cmp_ge),
        ]),
        ('Logic', [
            ('AND true',           test_and_true),
            ('AND false',          test_and_false),
            ('OR true',            test_or_true),
            ('OR false',           test_or_false),
            ('NOT true',           test_not_true),
            ('NOT false',          test_not_false),
        ]),
        ('Control Flow', [
            ('JMP',                test_jmp),
            ('JIF taken',          test_jif_taken),
            ('JIF not taken',      test_jif_not_taken),
            ('JNF taken',          test_jnf_taken),
            ('JTABLE hit',         test_jtable_hit),
            ('JTABLE default',     test_jtable_default),
            ('LOOP sum 1..5',      test_loop),
        ]),
        ('Locals', [
            ('LOCAL_GET / SET',    test_locals),
            ('LOCAL_DEREF',        test_local_deref),
            ('LOCAL_DEREF_SET',    test_local_deref_set),
        ]),
        ('Functions', [
            ('CALL / RET',         test_call_ret),
            ('Recursive factorial',test_call_recursive),
            ('CALL_PTR',           test_call_ptr),
            ('TAIL_SELF',          test_tail_self),
        ]),
        ('Memory', [
            ('ALLOC / FREE',       test_alloc_free),
            ('STORE / LOAD int',   test_store_load_int),
            ('STORE / LOAD float', test_store_load_float),
            ('OFFSET',             test_offset),
            ('OOB access',         test_oob_access),
        ]),
        ('Heap', [
            ('Free-list reuse',    test_heap_free_list_reuse),
        ]),
        ('Execute State', [
            ('last_locals after HALT', test_last_locals_after_halt),
        ]),
        ('Structs', [
            ('STRUCT_NEW',         test_struct_new),
            ('STRUCT_STORE / LOAD', test_field_set_get),
            ('Field not found',    test_field_not_found),
        ]),
        ('Arrays', [
            ('ARRAY_NEW',          test_array_new),
            ('ARRAY_STORE / LOAD',  test_index_set_get),
            ('ARRAY_LEN',          test_array_len),
        ]),
        ('Type Introspection', [
            ('SIZEOF int',         test_sizeof_int),
            ('SIZEOF double',      test_sizeof_double),
            ('SIZEOF struct',      test_sizeof_struct),
            ('TYPEOF',             test_typeof),
            ('ALIGNOF int',        test_alignof_int),
            ('ALIGNOF struct',     test_alignof_struct),
            ('ENDIANOF little',    test_endianof_little),
            ('ENDIANOF big',       test_endianof_big),
            ('ENDIANOF struct',    test_endianof_struct),
        ]),
        ('IO', [
            ('IO_OPEN/WRITE/READ/CLOSE', test_io_write_read),
            ('IO invalid handle',  test_io_invalid_handle),
        ]),
        ('FFI', [
            ('FFI_LOAD/SYM/CALL',  test_ffi_load_sym_call),
            ('FFI_FREE',           test_ffi_free),
            ('FFI bad library',    test_ffi_bad_lib),
        ]),
        ('Boundary Crossing', [
            ('EMIT_CONST',         test_emit_const),
            ('EMIT_GLOBAL',        test_emit_global),
            ('EMIT_TYPE',          test_emit_type),
            ('Multiple EMIT_CONST',test_multiple_emit_consts),
            ('EMITFLUX plain substitution',      test_emitflux_plain),
            ('EMITFLUX ~$f-string codify',       test_emitflux_fstring_codify),
            ('EMITFLUX loop 4 globals',          test_emitflux_loop),
        ]),
        ('compiler.io', [
            ('compiler.io.console.print',   test_compiler_print),
            ('compiler.io.console.input',   test_compiler_input),
            ('compiler.io.readfile',         test_compiler_readfile),
            ('compiler.io.writefile binary', test_compiler_writefile_binary),
            ('compiler.io.writefile text',   test_compiler_writefile_text),
            ('compiler.io.writefile append', test_compiler_writefile_append),
            ('readfile missing',             test_compiler_readfile_missing),
            ('compiler.import.stdlib',       test_compiler_import_stdlib),
            ('compiler.import.local',        test_compiler_import_local),
            ('compiler.fpm.package',         test_compiler_fpm_package),
        ]),
        ('String Ops', [
            ('STR_LEN',            test_str_len),
            ('STR_LEN empty',      test_str_len_empty),
            ('STR_CAT',            test_str_cat),
            ('STR_SLICE',          test_str_slice),
            ('STR_EQ true',        test_str_eq_true),
            ('STR_EQ false',       test_str_eq_false),
            ('STR_FIND found',     test_str_find_found),
            ('STR_FIND not found', test_str_find_not_found),
            ('INT_TO_STR',         test_int_to_str),
            ('INT_TO_STR negative',test_int_to_str_negative),
            ('INT_TO_STR char',    test_int_to_str_char),
            ('STR_TO_INT',         test_str_to_int),
            ('STR_TO_INT hex',     test_str_to_int_hex),
            ('STR_TO_INT invalid', test_str_to_int_invalid),
        ]),
        ('Type Conversion', [
            ('CAST int->float',    test_cast_int_to_float),
            ('CAST float->int',    test_cast_float_to_int),
            ('CAST int->bool',     test_cast_int_to_bool),
            ('CAST zero->bool',    test_cast_zero_to_bool),
            ('CAST int->long',     test_cast_int_to_long),
            ('CAST int->ulong',    test_cast_int_to_ulong),
            ('CAST int->double',   test_cast_int_to_double),
            ('CAST int->char',     test_cast_int_to_char),
            ('BITCAST float->uint',test_bitcast_float_to_int),
            ('BITCAST uint->float',test_bitcast_int_to_float),
        ]),
        ('Diagnostics', [
            ('ASSERT pass',        test_assert_pass),
            ('ASSERT fail',        test_assert_fail),
            ('WARN',               test_warn),
            ('PANIC',              test_panic),
        ]),
        ('Edge Cases', [
            ('Stack underflow',    test_stack_underflow),
            ('Unknown function',   test_unknown_function),
            ('Unknown struct',     test_unknown_struct),
            ('Free invalid ptr',   test_free_invalid_ptr),
        ]),
    ]

    for section, cases in sections:
        print(f'\n{section}')
        print('-' * (len(section) + 2))
        for name, fn in cases:
            test(name, fn)

    total = _passed + _failed
    print(f'\n{_passed}/{total} passed')
    if _failed:
        print(f'{_failed} FAILED')
        sys.exit(1)
    else:
        print('All tests passed.')


if __name__ == '__main__':
    main()