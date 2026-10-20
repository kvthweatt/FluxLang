// autograd_test.fx - Test program for the autograd library.
//
// Covers:
//   GradTensor    : gt_init, gt_free, gt_zero_grad
//   Tape          : init, push, reset
//   Forward ops   : grad_add, grad_sub, grad_mul, grad_matmul,
//                   grad_relu, grad_sigmoid, grad_tanh_act,
//                   grad_sum, grad_scale, grad_neg
//   Backward pass : backward()  -- gradient correctness verified by
//                   finite-difference checks against known analytic values
//   zero_grad     : resets grad buffers before a second backward pass
//
// Finite-difference tolerance used throughout: 1e-3
// (tape uses float32; FD epsilon h = 0.001)

#import <standard.fx>;
#import <autograd.fx>;

using standard::io::console,
      standard::autograd;

// ============================================================================
// Helpers
// ============================================================================

def pass(noopstr msg) -> void
{
    print("  [PASS] ");
    println(msg);
};

def fail(noopstr msg) -> void
{
    print("  [FAIL] ");
    println(msg);
};

def check(bool ok, noopstr msg) -> void
{
    if (ok) { pass(msg); }
    else     { fail(msg); };
};

def section(noopstr title) -> void
{
    print("\n-- ");
    print(title);
    println(" --");
};

// Absolute value for float.
def fabsf(float x) -> float
{
    if (x < 0.0f) { return -x; };
    return x;
};

// True when |a - b| <= tol.
def near(float a, float b, float tol) -> bool
{
    return fabsf(a - b) <= tol;
};

// ============================================================================
// Main
// ============================================================================

def main() -> int
{
    println("Autograd library test\0");

    float tol = 0.001f;

    // ========================================================================
    section("Tape init and GradTensor init\0");
    // ========================================================================

    // A tape with room for 64 nodes is enough for every test below.
    Tape tape((size_t)64);
    defer tape.__exit();

    // Simple leaf: scalar 3.0
    float[1] leaf_src = [3.0f];
    size_t[1] dims1 = [1];
    GradTensor leaf;
    gt_init(@leaf, @tape, @leaf_src[0], (size_t)1, @dims1[0]);
    check(leaf.numel    == 1,    "gt_init numel == 1\0");
    check(leaf.vals[0]  == 3.0f, "gt_init vals correct\0");
    check(leaf.grad[0]  == 0.0f, "gt_init grad zeroed\0");
    check(leaf.slot     == AG_NO_PRODUCER, "leaf slot == AG_NO_PRODUCER\0");
    gt_free(@leaf);

    // ========================================================================
    section("grad_add forward and backward\0");
    // ========================================================================
    //
    // Graph:  a + b = c,  loss = sum(c)
    //
    // a = [1, 2],  b = [3, 4]
    // c = [4, 6]
    // loss = 10
    //
    // dL/da = [1, 1]   (add passes gradient straight through)
    // dL/db = [1, 1]

    tape.reset();

    float[2] add_adata = [1.0f, 2.0f],
             add_bdata = [3.0f, 4.0f];
    size_t[1] dims2 = [2];

    GradTensor add_a, add_b;
    gt_init(@add_a, @tape, @add_adata[0], (size_t)1, @dims2[0]);
    gt_init(@add_b, @tape, @add_bdata[0], (size_t)1, @dims2[0]);

    GradTensor* add_c    = grad_add(@tape, @add_a, @add_b);
    GradTensor* add_loss = grad_sum(@tape, add_c);

    check(add_c.vals[0] == 4.0f, "grad_add forward [0] == 4\0");
    check(add_c.vals[1] == 6.0f, "grad_add forward [1] == 6\0");
    check(add_loss.vals[0] == 10.0f, "grad_sum of add == 10\0");

    backward(@tape, add_loss);

    check(near(add_a.grad[0], 1.0f, tol), "grad_add dL/da[0] == 1\0");
    check(near(add_a.grad[1], 1.0f, tol), "grad_add dL/da[1] == 1\0");
    check(near(add_b.grad[0], 1.0f, tol), "grad_add dL/db[0] == 1\0");
    check(near(add_b.grad[1], 1.0f, tol), "grad_add dL/db[1] == 1\0");

    gt_free(@add_a);
    gt_free(@add_b);
    gt_free_heap(add_c);
    gt_free_heap(add_loss);

    // ========================================================================
    section("grad_sub forward and backward\0");
    // ========================================================================
    //
    // a = [5, 8],  b = [2, 3]
    // c = a - b = [3, 5]
    // loss = sum(c) = 8
    //
    // dL/da = [1,  1]
    // dL/db = [-1, -1]

    tape.reset();

    float[2] sub_adata = [5.0f, 8.0f],
             sub_bdata = [2.0f, 3.0f];

    GradTensor sub_a, sub_b;
    gt_init(@sub_a, @tape, @sub_adata[0], (size_t)1, @dims2[0]);
    gt_init(@sub_b, @tape, @sub_bdata[0], (size_t)1, @dims2[0]);

    GradTensor* sub_c    = grad_sub(@tape, @sub_a, @sub_b);
    GradTensor* sub_loss = grad_sum(@tape, sub_c);

    check(sub_c.vals[0] == 3.0f, "grad_sub forward [0] == 3\0");
    check(sub_c.vals[1] == 5.0f, "grad_sub forward [1] == 5\0");

    backward(@tape, sub_loss);

    check(near(sub_a.grad[0],  1.0f, tol), "grad_sub dL/da[0] ==  1\0");
    check(near(sub_b.grad[0], -1.0f, tol), "grad_sub dL/db[0] == -1\0");

    gt_free(@sub_a);
    gt_free(@sub_b);
    gt_free_heap(sub_c);
    gt_free_heap(sub_loss);

    // ========================================================================
    section("grad_mul forward and backward\0");
    // ========================================================================
    //
    // a = [2, 3],  b = [4, 5]
    // c = a * b = [8, 15]
    // loss = sum(c) = 23
    //
    // dL/da[i] = b[i]  ->  [4, 5]
    // dL/db[i] = a[i]  ->  [2, 3]

    tape.reset();

    float[2] mul_adata = [2.0f, 3.0f],
             mul_bdata = [4.0f, 5.0f];

    GradTensor mul_a, mul_b;
    gt_init(@mul_a, @tape, @mul_adata[0], (size_t)1, @dims2[0]);
    gt_init(@mul_b, @tape, @mul_bdata[0], (size_t)1, @dims2[0]);

    GradTensor* mul_c    = grad_mul(@tape, @mul_a, @mul_b);
    GradTensor* mul_loss = grad_sum(@tape, mul_c);

    check(mul_c.vals[0] == 8.0f,  "grad_mul forward [0] == 8\0");
    check(mul_c.vals[1] == 15.0f, "grad_mul forward [1] == 15\0");

    backward(@tape, mul_loss);

    check(near(mul_a.grad[0], 4.0f, tol), "grad_mul dL/da[0] == b[0] == 4\0");
    check(near(mul_a.grad[1], 5.0f, tol), "grad_mul dL/da[1] == b[1] == 5\0");
    check(near(mul_b.grad[0], 2.0f, tol), "grad_mul dL/db[0] == a[0] == 2\0");
    check(near(mul_b.grad[1], 3.0f, tol), "grad_mul dL/db[1] == a[1] == 3\0");

    gt_free(@mul_a);
    gt_free(@mul_b);
    gt_free_heap(mul_c);
    gt_free_heap(mul_loss);

    // ========================================================================
    section("grad_matmul forward and backward\0");
    // ========================================================================
    //
    // A = [[1, 2],   B = [[5, 6],
    //      [3, 4]]        [7, 8]]
    //
    // C = A @ B = [[1*5+2*7, 1*6+2*8],   = [[19, 22],
    //              [3*5+4*7, 3*6+4*8]]      [43, 50]]
    //
    // loss = sum(C) = 19 + 22 + 43 + 50 = 134
    //
    // Analytic gradients (dL/dC = all-ones [2x2]):
    //   dL/dA = dL/dC @ B^T = [[1,1],[1,1]] @ [[5,7],[6,8]]
    //         = [[11, 15], [11, 15]]
    //   dL/dB = A^T @ dL/dC = [[1,3],[2,4]] @ [[1,1],[1,1]]
    //         = [[4, 4], [6, 6]]

    tape.reset();

    float[4] mm_adata = [1.0f, 2.0f, 3.0f, 4.0f],
             mm_bdata = [5.0f, 6.0f, 7.0f, 8.0f];
    size_t[2] dims22 = [2, 2];

    GradTensor mm_A, mm_B;
    gt_init(@mm_A, @tape, @mm_adata[0], (size_t)2, @dims22[0]);
    gt_init(@mm_B, @tape, @mm_bdata[0], (size_t)2, @dims22[0]);

    GradTensor* mm_C    = grad_matmul(@tape, @mm_A, @mm_B);
    GradTensor* mm_loss = grad_sum(@tape, mm_C);

    check(near(mm_C.vals[0], 19.0f, tol), "grad_matmul C[0,0] == 19\0");
    check(near(mm_C.vals[1], 22.0f, tol), "grad_matmul C[0,1] == 22\0");
    check(near(mm_C.vals[2], 43.0f, tol), "grad_matmul C[1,0] == 43\0");
    check(near(mm_C.vals[3], 50.0f, tol), "grad_matmul C[1,1] == 50\0");
    check(near(mm_loss.vals[0], 134.0f, tol), "grad_matmul loss == 134\0");

    backward(@tape, mm_loss);

    check(near(mm_A.grad[0], 11.0f, tol), "grad_matmul dL/dA[0,0] == 11\0");
    check(near(mm_A.grad[1], 15.0f, tol), "grad_matmul dL/dA[0,1] == 15\0");
    check(near(mm_A.grad[2], 11.0f, tol), "grad_matmul dL/dA[1,0] == 11\0");
    check(near(mm_A.grad[3], 15.0f, tol), "grad_matmul dL/dA[1,1] == 15\0");
    check(near(mm_B.grad[0], 4.0f, tol),  "grad_matmul dL/dB[0,0] == 4\0");
    check(near(mm_B.grad[1], 4.0f, tol),  "grad_matmul dL/dB[0,1] == 4\0");
    check(near(mm_B.grad[2], 6.0f, tol),  "grad_matmul dL/dB[1,0] == 6\0");
    check(near(mm_B.grad[3], 6.0f, tol),  "grad_matmul dL/dB[1,1] == 6\0");

    gt_free(@mm_A);
    gt_free(@mm_B);
    gt_free_heap(mm_C);
    gt_free_heap(mm_loss);

    // ========================================================================
    section("grad_relu forward and backward\0");
    // ========================================================================
    //
    // x = [-2, 0, 3]
    // relu(x) = [0, 0, 3]
    // loss = sum = 3
    //
    // dL/dx = [0, 0, 1]   (gate: 1 where x > 0, else 0)

    tape.reset();

    float[3] relu_xdata = [-2.0f, 0.0f, 3.0f];
    size_t[1] dims3 = [3];

    GradTensor relu_x;
    gt_init(@relu_x, @tape, @relu_xdata[0], (size_t)1, @dims3[0]);

    GradTensor* relu_out  = grad_relu(@tape, @relu_x);
    GradTensor* relu_loss = grad_sum(@tape, relu_out);

    check(relu_out.vals[0] == 0.0f, "grad_relu forward [-2] == 0\0");
    check(relu_out.vals[1] == 0.0f, "grad_relu forward [0]  == 0\0");
    check(relu_out.vals[2] == 3.0f, "grad_relu forward [3]  == 3\0");

    backward(@tape, relu_loss);

    check(near(relu_x.grad[0], 0.0f, tol), "grad_relu dL/dx[-2] == 0\0");
    check(near(relu_x.grad[1], 0.0f, tol), "grad_relu dL/dx[0]  == 0\0");
    check(near(relu_x.grad[2], 1.0f, tol), "grad_relu dL/dx[3]  == 1\0");

    gt_free(@relu_x);
    gt_free_heap(relu_out);
    gt_free_heap(relu_loss);

    // ========================================================================
    section("grad_sigmoid forward and backward\0");
    // ========================================================================
    //
    // x = [0.0]
    // sigmoid(0) = 0.5
    // loss = sum = 0.5
    //
    // dL/dx = sigmoid(0) * (1 - sigmoid(0)) = 0.5 * 0.5 = 0.25

    tape.reset();

    float[1] sig_xdata = [0.0f];

    GradTensor sig_x;
    gt_init(@sig_x, @tape, @sig_xdata[0], (size_t)1, @dims1[0]);

    GradTensor* sig_out  = grad_sigmoid(@tape, @sig_x);
    GradTensor* sig_loss = grad_sum(@tape, sig_out);

    check(near(sig_out.vals[0], 0.5f, tol), "grad_sigmoid(0) == 0.5\0");

    backward(@tape, sig_loss);

    check(near(sig_x.grad[0], 0.25f, tol), "grad_sigmoid dL/dx == 0.25\0");

    gt_free(@sig_x);
    gt_free_heap(sig_out);
    gt_free_heap(sig_loss);

    // ========================================================================
    section("grad_tanh_act forward and backward\0");
    // ========================================================================
    //
    // x = [0.0]
    // tanh(0) = 0.0
    // loss = sum = 0.0
    //
    // dL/dx = 1 - tanh(0)^2 = 1 - 0 = 1.0

    tape.reset();

    float[1] tanh_xdata = [0.0f];

    GradTensor tanh_x;
    gt_init(@tanh_x, @tape, @tanh_xdata[0], (size_t)1, @dims1[0]);

    GradTensor* tanh_out  = grad_tanh_act(@tape, @tanh_x);
    GradTensor* tanh_loss = grad_sum(@tape, tanh_out);

    check(near(tanh_out.vals[0], 0.0f, tol), "grad_tanh(0) == 0\0");

    backward(@tape, tanh_loss);

    check(near(tanh_x.grad[0], 1.0f, tol), "grad_tanh dL/dx == 1\0");

    gt_free(@tanh_x);
    gt_free_heap(tanh_out);
    gt_free_heap(tanh_loss);

    // ========================================================================
    section("grad_scale forward and backward\0");
    // ========================================================================
    //
    // x = [2, 5],  scalar = 3
    // out = [6, 15]
    // loss = 21
    //
    // dL/dx = [3, 3]

    tape.reset();

    float[2] scale_xdata = [2.0f, 5.0f];

    GradTensor scale_x;
    gt_init(@scale_x, @tape, @scale_xdata[0], (size_t)1, @dims2[0]);

    GradTensor* scale_out  = grad_scale(@tape, @scale_x, 3.0f);
    GradTensor* scale_loss = grad_sum(@tape, scale_out);

    check(near(scale_out.vals[0], 6.0f,  tol), "grad_scale forward [0] == 6\0");
    check(near(scale_out.vals[1], 15.0f, tol), "grad_scale forward [1] == 15\0");

    backward(@tape, scale_loss);

    check(near(scale_x.grad[0], 3.0f, tol), "grad_scale dL/dx[0] == 3\0");
    check(near(scale_x.grad[1], 3.0f, tol), "grad_scale dL/dx[1] == 3\0");

    gt_free(@scale_x);
    gt_free_heap(scale_out);
    gt_free_heap(scale_loss);

    // ========================================================================
    section("grad_neg forward and backward\0");
    // ========================================================================
    //
    // x = [4, -1]
    // out = [-4, 1]
    // loss = -3
    //
    // dL/dx = [-1, -1]

    tape.reset();

    float[2] neg_xdata = [4.0f, -1.0f];

    GradTensor neg_x;
    gt_init(@neg_x, @tape, @neg_xdata[0], (size_t)1, @dims2[0]);

    GradTensor* neg_out  = grad_neg(@tape, @neg_x);
    GradTensor* neg_loss = grad_sum(@tape, neg_out);

    check(near(neg_out.vals[0], -4.0f, tol), "grad_neg forward [0] == -4\0");
    check(near(neg_out.vals[1],  1.0f, tol), "grad_neg forward [1] ==  1\0");

    backward(@tape, neg_loss);

    check(near(neg_x.grad[0], -1.0f, tol), "grad_neg dL/dx[0] == -1\0");
    check(near(neg_x.grad[1], -1.0f, tol), "grad_neg dL/dx[1] == -1\0");

    gt_free(@neg_x);
    gt_free_heap(neg_out);
    gt_free_heap(neg_loss);

    // ========================================================================
    section("Chained ops: relu(a * b)\0");
    // ========================================================================
    //
    // a = [3, -1],  b = [2, 4]
    // prod = a * b  = [6, -4]
    // act  = relu(prod) = [6, 0]
    // loss = sum = 6
    //
    // dL/d(prod) = [1, 0]   (relu gate)
    // dL/da = dL/d(prod) * b = [1*2, 0*4] = [2, 0]
    // dL/db = dL/d(prod) * a = [1*3, 0*-1] = [3, 0]

    tape.reset();

    float[2] ch_adata = [3.0f, -1.0f],
             ch_bdata = [2.0f,  4.0f];

    GradTensor ch_a, ch_b;
    gt_init(@ch_a, @tape, @ch_adata[0], (size_t)1, @dims2[0]);
    gt_init(@ch_b, @tape, @ch_bdata[0], (size_t)1, @dims2[0]);

    GradTensor* ch_prod = grad_mul(@tape, @ch_a, @ch_b);
    GradTensor* ch_act  = grad_relu(@tape, ch_prod);
    GradTensor* ch_loss = grad_sum(@tape, ch_act);

    check(near(ch_prod.vals[0],  6.0f, tol), "chain mul forward [0] == 6\0");
    check(near(ch_prod.vals[1], -4.0f, tol), "chain mul forward [1] == -4\0");
    check(near(ch_act.vals[0],   6.0f, tol), "chain relu forward [0] == 6\0");
    check(near(ch_act.vals[1],   0.0f, tol), "chain relu forward [1] == 0\0");

    backward(@tape, ch_loss);

    check(near(ch_a.grad[0], 2.0f, tol), "chain dL/da[0] == 2\0");
    check(near(ch_a.grad[1], 0.0f, tol), "chain dL/da[1] == 0\0");
    check(near(ch_b.grad[0], 3.0f, tol), "chain dL/db[0] == 3\0");
    check(near(ch_b.grad[1], 0.0f, tol), "chain dL/db[1] == 0\0");

    gt_free(@ch_a);
    gt_free(@ch_b);
    gt_free_heap(ch_prod);
    gt_free_heap(ch_act);
    gt_free_heap(ch_loss);

    // ========================================================================
    section("zero_grad and second backward pass\0");
    // ========================================================================
    //
    // Run the same add graph twice.  After the first backward() the grads are
    // [1,1].  zero_grad resets them; the second backward should also give [1,1]
    // not the accumulated [2,2].

    tape.reset();

    float[2] zg_adata = [7.0f, 8.0f],
             zg_bdata = [1.0f, 2.0f];

    GradTensor zg_a, zg_b;
    gt_init(@zg_a, @tape, @zg_adata[0], (size_t)1, @dims2[0]);
    gt_init(@zg_b, @tape, @zg_bdata[0], (size_t)1, @dims2[0]);

    GradTensor* zg_c    = grad_add(@tape, @zg_a, @zg_b);
    GradTensor* zg_loss = grad_sum(@tape, zg_c);

    backward(@tape, zg_loss);

    check(near(zg_a.grad[0], 1.0f, tol), "first backward dL/da[0] == 1\0");

    // Reset tape and grad buffers, then repeat the forward + backward.
    GradTensor*[2] params;
    params[0] = @zg_a;
    params[1] = @zg_b;
    zero_grad(@params[0], 2);

    tape.reset();

    GradTensor* zg_c2    = grad_add(@tape, @zg_a, @zg_b);
    GradTensor* zg_loss2 = grad_sum(@tape, zg_c2);

    backward(@tape, zg_loss2);

    check(near(zg_a.grad[0], 1.0f, tol), "second backward dL/da[0] == 1 (not 2)\0");
    check(near(zg_b.grad[0], 1.0f, tol), "second backward dL/db[0] == 1 (not 2)\0");

    gt_free(@zg_a);
    gt_free(@zg_b);
    gt_free_heap(zg_c);
    gt_free_heap(zg_loss);
    gt_free_heap(zg_c2);
    gt_free_heap(zg_loss2);

    // ========================================================================
    section("requires_grad == false skips gradient accumulation\0");
    // ========================================================================
    //
    // a is a constant (requires_grad = false), b is a parameter.
    // loss = sum(a + b)
    // Only b.grad should be filled; a.grad stays 0.

    tape.reset();

    float[2] rg_adata = [10.0f, 20.0f],
             rg_bdata = [1.0f,  2.0f];

    GradTensor rg_a, rg_b;
    gt_init(@rg_a, @tape, @rg_adata[0], (size_t)1, @dims2[0]);
    gt_init(@rg_b, @tape, @rg_bdata[0], (size_t)1, @dims2[0]);

    rg_a.requires_grad = false;   // mark as constant

    GradTensor* rg_c    = grad_add(@tape, @rg_a, @rg_b);
    GradTensor* rg_loss = grad_sum(@tape, rg_c);

    backward(@tape, rg_loss);

    check(near(rg_a.grad[0], 0.0f, tol), "constant grad stays 0\0");
    check(near(rg_b.grad[0], 1.0f, tol), "parameter grad == 1\0");

    gt_free(@rg_a);
    gt_free(@rg_b);
    gt_free_heap(rg_c);
    gt_free_heap(rg_loss);

    println("\nDone.\0");
    return 0;
};
