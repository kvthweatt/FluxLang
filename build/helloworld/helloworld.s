	.text
	.file	"helloworld.ll"
	.globl	__static_init                   # -- Begin function __static_init
	.p2align	4, 0x90
	.type	__static_init,@function
__static_init:                          # @__static_init
	.cfi_startproc
# %bb.0:                                # %entry
	retq
.Lfunc_end0:
	.size	__static_init, .Lfunc_end0-__static_init
	.cfi_endproc
                                        # -- End function
	.globl	standard__types__bswap16__1__u16__ret_u16 # -- Begin function standard__types__bswap16__1__u16__ret_u16
	.p2align	4, 0x90
	.type	standard__types__bswap16__1__u16__ret_u16,@function
standard__types__bswap16__1__u16__ret_u16: # @standard__types__bswap16__1__u16__ret_u16
	.cfi_startproc
# %bb.0:                                # %entry
	movl	%edi, %ecx
	movw	%cx, -2(%rsp)
	movzbl	%ch, %eax
	shll	$8, %ecx
	orl	%ecx, %eax
                                        # kill: def $ax killed $ax killed $eax
	retq
.Lfunc_end1:
	.size	standard__types__bswap16__1__u16__ret_u16, .Lfunc_end1-standard__types__bswap16__1__u16__ret_u16
	.cfi_endproc
                                        # -- End function
	.globl	standard__types__bswap32__1__u32__ret_u32 # -- Begin function standard__types__bswap32__1__u32__ret_u32
	.p2align	4, 0x90
	.type	standard__types__bswap32__1__u32__ret_u32,@function
standard__types__bswap32__1__u32__ret_u32: # @standard__types__bswap32__1__u32__ret_u32
	.cfi_startproc
# %bb.0:                                # %entry
	movl	%edi, -4(%rsp)
	movl	%edi, %eax
	shll	$24, %eax
	movl	%edi, %ecx
	andl	$65280, %ecx                    # imm = 0xFF00
	shll	$8, %ecx
	orl	%eax, %ecx
	movl	%edi, %eax
	shrl	$8, %eax
	andl	$65280, %eax                    # imm = 0xFF00
	orl	%ecx, %eax
	shrl	$24, %edi
	orl	%edi, %eax
	retq
.Lfunc_end2:
	.size	standard__types__bswap32__1__u32__ret_u32, .Lfunc_end2-standard__types__bswap32__1__u32__ret_u32
	.cfi_endproc
                                        # -- End function
	.globl	standard__types__bswap64__1__u64__ret_u64 # -- Begin function standard__types__bswap64__1__u64__ret_u64
	.p2align	4, 0x90
	.type	standard__types__bswap64__1__u64__ret_u64,@function
standard__types__bswap64__1__u64__ret_u64: # @standard__types__bswap64__1__u64__ret_u64
	.cfi_startproc
# %bb.0:                                # %entry
	movq	%rdi, -8(%rsp)
	movq	%rdi, %rax
	shlq	$56, %rax
	movl	%edi, %ecx
	andl	$65280, %ecx                    # imm = 0xFF00
	shlq	$40, %rcx
	orq	%rax, %rcx
	movl	%edi, %eax
	andl	$16711680, %eax                 # imm = 0xFF0000
	shlq	$24, %rax
	orq	%rcx, %rax
	movl	%edi, %ecx
	andl	$-16777216, %ecx                # imm = 0xFF000000
	shlq	$8, %rcx
	orq	%rax, %rcx
	movq	%rdi, %rax
	shrq	$8, %rax
	andl	$-16777216, %eax                # imm = 0xFF000000
	orq	%rcx, %rax
	movq	%rdi, %rcx
	shrq	$24, %rcx
	andl	$16711680, %ecx                 # imm = 0xFF0000
	orq	%rax, %rcx
	movq	%rdi, %rax
	shrq	$40, %rax
	andl	$65280, %eax                    # imm = 0xFF00
	orq	%rcx, %rax
	shrq	$56, %rdi
	orq	%rdi, %rax
	retq
.Lfunc_end3:
	.size	standard__types__bswap64__1__u64__ret_u64, .Lfunc_end3-standard__types__bswap64__1__u64__ret_u64
	.cfi_endproc
                                        # -- End function
	.globl	standard__types__ntoh16__1__be16__ret_le16 # -- Begin function standard__types__ntoh16__1__be16__ret_le16
	.p2align	4, 0x90
	.type	standard__types__ntoh16__1__be16__ret_le16,@function
standard__types__ntoh16__1__be16__ret_le16: # @standard__types__ntoh16__1__be16__ret_le16
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rax
	.cfi_def_cfa_offset 16
	movw	%di, 6(%rsp)
	callq	standard__types__bswap16__1__u16__ret_u16@PLT
	popq	%rcx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end4:
	.size	standard__types__ntoh16__1__be16__ret_le16, .Lfunc_end4-standard__types__ntoh16__1__be16__ret_le16
	.cfi_endproc
                                        # -- End function
	.globl	standard__types__ntoh32__1__be32__ret_le32 # -- Begin function standard__types__ntoh32__1__be32__ret_le32
	.p2align	4, 0x90
	.type	standard__types__ntoh32__1__be32__ret_le32,@function
standard__types__ntoh32__1__be32__ret_le32: # @standard__types__ntoh32__1__be32__ret_le32
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rax
	.cfi_def_cfa_offset 16
	movl	%edi, 4(%rsp)
	callq	standard__types__bswap32__1__u32__ret_u32@PLT
	popq	%rcx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end5:
	.size	standard__types__ntoh32__1__be32__ret_le32, .Lfunc_end5-standard__types__ntoh32__1__be32__ret_le32
	.cfi_endproc
                                        # -- End function
	.globl	standard__types__hton16__1__le16__ret_be16 # -- Begin function standard__types__hton16__1__le16__ret_be16
	.p2align	4, 0x90
	.type	standard__types__hton16__1__le16__ret_be16,@function
standard__types__hton16__1__le16__ret_be16: # @standard__types__hton16__1__le16__ret_be16
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rax
	.cfi_def_cfa_offset 16
	movw	%di, 6(%rsp)
	callq	standard__types__bswap16__1__u16__ret_u16@PLT
	popq	%rcx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end6:
	.size	standard__types__hton16__1__le16__ret_be16, .Lfunc_end6-standard__types__hton16__1__le16__ret_be16
	.cfi_endproc
                                        # -- End function
	.globl	standard__types__hton32__1__le32__ret_be32 # -- Begin function standard__types__hton32__1__le32__ret_be32
	.p2align	4, 0x90
	.type	standard__types__hton32__1__le32__ret_be32,@function
standard__types__hton32__1__le32__ret_be32: # @standard__types__hton32__1__le32__ret_be32
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rax
	.cfi_def_cfa_offset 16
	movl	%edi, 4(%rsp)
	callq	standard__types__bswap32__1__u32__ret_u32@PLT
	popq	%rcx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end7:
	.size	standard__types__hton32__1__le32__ret_be32, .Lfunc_end7-standard__types__hton32__1__le32__ret_be32
	.cfi_endproc
                                        # -- End function
	.globl	standard__types__bit_test__2__u32__u32__ret_bool # -- Begin function standard__types__bit_test__2__u32__u32__ret_bool
	.p2align	4, 0x90
	.type	standard__types__bit_test__2__u32__u32__ret_bool,@function
standard__types__bit_test__2__u32__u32__ret_bool: # @standard__types__bit_test__2__u32__u32__ret_bool
	.cfi_startproc
# %bb.0:                                # %entry
	movl	%edi, -4(%rsp)
	movl	%esi, -8(%rsp)
	btl	%esi, %edi
	setb	%al
	retq
.Lfunc_end8:
	.size	standard__types__bit_test__2__u32__u32__ret_bool, .Lfunc_end8-standard__types__bit_test__2__u32__u32__ret_bool
	.cfi_endproc
                                        # -- End function
	.globl	standard__types__align_up__2__u64__u64__ret_u64 # -- Begin function standard__types__align_up__2__u64__u64__ret_u64
	.p2align	4, 0x90
	.type	standard__types__align_up__2__u64__u64__ret_u64,@function
standard__types__align_up__2__u64__u64__ret_u64: # @standard__types__align_up__2__u64__u64__ret_u64
	.cfi_startproc
# %bb.0:                                # %entry
	movq	%rdi, -8(%rsp)
	movq	%rsi, -16(%rsp)
	leaq	(%rsi,%rdi), %rcx
	decq	%rcx
	leaq	-1(%rsi), %rax
	andq	%rcx, %rax
	retq
.Lfunc_end9:
	.size	standard__types__align_up__2__u64__u64__ret_u64, .Lfunc_end9-standard__types__align_up__2__u64__u64__ret_u64
	.cfi_endproc
                                        # -- End function
	.globl	standard__types__align_down__2__u64__u64__ret_u64 # -- Begin function standard__types__align_down__2__u64__u64__ret_u64
	.p2align	4, 0x90
	.type	standard__types__align_down__2__u64__u64__ret_u64,@function
standard__types__align_down__2__u64__u64__ret_u64: # @standard__types__align_down__2__u64__u64__ret_u64
	.cfi_startproc
# %bb.0:                                # %entry
	movq	%rdi, -8(%rsp)
	movq	%rsi, -16(%rsp)
	leaq	-1(%rsi), %rax
	andq	%rdi, %rax
	retq
.Lfunc_end10:
	.size	standard__types__align_down__2__u64__u64__ret_u64, .Lfunc_end10-standard__types__align_down__2__u64__u64__ret_u64
	.cfi_endproc
                                        # -- End function
	.globl	standard__types__is_aligned__2__u64__u64__ret_bool # -- Begin function standard__types__is_aligned__2__u64__u64__ret_bool
	.p2align	4, 0x90
	.type	standard__types__is_aligned__2__u64__u64__ret_bool,@function
standard__types__is_aligned__2__u64__u64__ret_bool: # @standard__types__is_aligned__2__u64__u64__ret_bool
	.cfi_startproc
# %bb.0:                                # %entry
	movq	%rdi, -8(%rsp)
	movq	%rsi, -16(%rsp)
	decq	%rsi
	testq	%rsi, %rdi
	sete	%al
	retq
.Lfunc_end11:
	.size	standard__types__is_aligned__2__u64__u64__ret_bool, .Lfunc_end11-standard__types__is_aligned__2__u64__u64__ret_bool
	.cfi_endproc
                                        # -- End function
	.globl	strlen__1__byte_ptr1__ret_int   # -- Begin function strlen__1__byte_ptr1__ret_int
	.p2align	4, 0x90
	.type	strlen__1__byte_ptr1__ret_int,@function
strlen__1__byte_ptr1__ret_int:          # @strlen__1__byte_ptr1__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	subq	$16, %rsp
	movq	%rdi, -16(%rbp)
	movl	$0, -4(%rbp)
	.p2align	4, 0x90
.LBB12_1:                               # %while.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	%rsp, %rax
	leaq	-16(%rax), %rsp
	movq	-16(%rbp), %rcx
	leaq	1(%rcx), %rdx
	movq	%rdx, -16(%rbp)
	movq	%rcx, -16(%rax)
	cmpb	$0, (%rcx)
	je	.LBB12_2
# %bb.3:                                # %else
                                        #   in Loop: Header=BB12_1 Depth=1
	incl	-4(%rbp)
	jmp	.LBB12_1
.LBB12_2:                               # %while.end
	movl	-4(%rbp), %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end12:
	.size	strlen__1__byte_ptr1__ret_int, .Lfunc_end12-strlen__1__byte_ptr1__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	strcpy__2__noopstr__noopstr__ret_noopstr # -- Begin function strcpy__2__noopstr__noopstr__ret_noopstr
	.p2align	4, 0x90
	.type	strcpy__2__noopstr__noopstr__ret_noopstr,@function
strcpy__2__noopstr__noopstr__ret_noopstr: # @strcpy__2__noopstr__noopstr__ret_noopstr
	.cfi_startproc
# %bb.0:                                # %entry
	movq	%rdi, -16(%rsp)
	movq	%rsi, -8(%rsp)
	movq	$0, -24(%rsp)
	movq	-8(%rsp), %rax
	movslq	-24(%rsp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB13_3
	.p2align	4, 0x90
.LBB13_2:                               # %while.body
                                        # =>This Inner Loop Header: Depth=1
	movq	-8(%rsp), %rax
	movq	-24(%rsp), %rcx
	movslq	%ecx, %rdx
	movzbl	(%rax,%rdx), %eax
	movq	-16(%rsp), %rdx
	movb	%al, (%rdx,%rcx)
	incq	-24(%rsp)
	movq	-8(%rsp), %rax
	movslq	-24(%rsp), %rcx
	cmpb	$0, (%rax,%rcx)
	jne	.LBB13_2
.LBB13_3:                               # %while.end
	movq	-16(%rsp), %rax
	movq	-24(%rsp), %rcx
	movb	$0, (%rax,%rcx)
	movq	-16(%rsp), %rax
	retq
.Lfunc_end13:
	.size	strcpy__2__noopstr__noopstr__ret_noopstr, .Lfunc_end13-strcpy__2__noopstr__noopstr__ret_noopstr
	.cfi_endproc
                                        # -- End function
	.globl	i32str__2__i32__byte_ptr1__ret_i32 # -- Begin function i32str__2__i32__byte_ptr1__ret_i32
	.p2align	4, 0x90
	.type	i32str__2__i32__byte_ptr1__ret_i32,@function
i32str__2__i32__byte_ptr1__ret_i32:     # @i32str__2__i32__byte_ptr1__ret_i32
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	subq	$16, %rsp
	movl	%edi, -4(%rbp)
	movq	%rsi, -16(%rbp)
	testl	%edi, %edi
	je	.LBB14_1
# %bb.2:                                # %else
	movq	%rsp, %rax
	leaq	-16(%rax), %rcx
	movq	%rcx, %rsp
	movl	$0, -16(%rax)
	cmpl	$0, -4(%rbp)
	jns	.LBB14_4
# %bb.3:                                # %then.1
	movl	$1, (%rcx)
	negl	-4(%rbp)
.LBB14_4:                               # %ifcont.1
	movq	%rsp, %rax
	leaq	-16(%rax), %rdx
	movq	%rdx, %rsp
	movl	$0, -16(%rax)
	movq	%rsp, %rax
	addq	$-32, %rax
	movq	%rax, %rsp
	cmpl	$0, -4(%rbp)
	jle	.LBB14_7
	.p2align	4, 0x90
.LBB14_6:                               # %while.body
                                        # =>This Inner Loop Header: Depth=1
	movslq	-4(%rbp), %rsi
	imulq	$1717986919, %rsi, %rdi         # imm = 0x66666667
	movq	%rdi, %r8
	shrq	$63, %r8
	shrq	$34, %rdi
	addl	%r8d, %edi
	addl	%edi, %edi
	leal	(%rdi,%rdi,4), %edi
	subl	%edi, %esi
	addb	$48, %sil
	movslq	(%rdx), %rdi
	movb	%sil, (%rax,%rdi)
	movslq	-4(%rbp), %rsi
	imulq	$1717986919, %rsi, %rsi         # imm = 0x66666667
	movq	%rsi, %rdi
	shrq	$63, %rdi
	sarq	$34, %rsi
	addl	%edi, %esi
	movl	%esi, -4(%rbp)
	incl	(%rdx)
	cmpl	$0, -4(%rbp)
	jg	.LBB14_6
.LBB14_7:                               # %while.end
	movq	%rsp, %rdi
	leaq	-16(%rdi), %rsi
	movq	%rsi, %rsp
	movl	$0, -16(%rdi)
	cmpl	$1, (%rcx)
	jne	.LBB14_9
# %bb.8:                                # %then.2
	movq	-16(%rbp), %rcx
	movb	$45, (%rcx)
	movl	$1, (%rsi)
.LBB14_9:                               # %ifcont.2
	movq	%rsp, %rdi
	leaq	-16(%rdi), %rcx
	movq	%rcx, %rsp
	movl	(%rdx), %edx
	decl	%edx
	movl	%edx, -16(%rdi)
	cmpl	$0, (%rcx)
	js	.LBB14_12
	.p2align	4, 0x90
.LBB14_11:                              # %while.body.1
                                        # =>This Inner Loop Header: Depth=1
	movslq	(%rcx), %rdx
	movzbl	(%rax,%rdx), %edx
	movq	-16(%rbp), %rdi
	movslq	(%rsi), %r8
	movb	%dl, (%rdi,%r8)
	incl	(%rsi)
	decl	(%rcx)
	cmpl	$0, (%rcx)
	jns	.LBB14_11
.LBB14_12:                              # %while.end.1
	movq	-16(%rbp), %rax
	movslq	(%rsi), %rcx
	movb	$0, (%rax,%rcx)
	movl	(%rsi), %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB14_1:                               # %then
	.cfi_def_cfa %rbp, 16
	movq	-16(%rbp), %rax
	movb	$48, (%rax)
	movq	-16(%rbp), %rax
	movb	$0, 1(%rax)
	movl	$1, %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end14:
	.size	i32str__2__i32__byte_ptr1__ret_i32, .Lfunc_end14-i32str__2__i32__byte_ptr1__ret_i32
	.cfi_endproc
                                        # -- End function
	.globl	i64str__2__i64__byte_ptr1__ret_i64 # -- Begin function i64str__2__i64__byte_ptr1__ret_i64
	.p2align	4, 0x90
	.type	i64str__2__i64__byte_ptr1__ret_i64,@function
i64str__2__i64__byte_ptr1__ret_i64:     # @i64str__2__i64__byte_ptr1__ret_i64
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	subq	$16, %rsp
	movq	%rdi, -8(%rbp)
	movq	%rsi, -16(%rbp)
	testq	%rdi, %rdi
	jne	.LBB15_2
# %bb.1:                                # %then
	movq	-16(%rbp), %rax
	movb	$48, (%rax)
	movq	-16(%rbp), %rax
	movb	$0, 1(%rax)
	movl	$1, %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB15_2:                               # %else
	.cfi_def_cfa %rbp, 16
	movq	%rsp, %rax
	leaq	-16(%rax), %rsi
	movq	%rsi, %rsp
	movq	$0, -16(%rax)
	cmpq	$0, -8(%rbp)
	jns	.LBB15_4
# %bb.3:                                # %then.1
	movq	$1, (%rsi)
	negq	-8(%rbp)
.LBB15_4:                               # %ifcont.1
	movq	%rsp, %rax
	leaq	-16(%rax), %rdi
	movq	%rdi, %rsp
	movq	$0, -16(%rax)
	movq	%rsp, %rcx
	addq	$-32, %rcx
	movq	%rcx, %rsp
	movl	$10, %r8d
	cmpq	$0, -8(%rbp)
	jg	.LBB15_6
	jmp	.LBB15_13
	.p2align	4, 0x90
.LBB15_10:                              #   in Loop: Header=BB15_6 Depth=1
                                        # kill: def $eax killed $eax killed $rax
	xorl	%edx, %edx
	divl	%r8d
                                        # kill: def $eax killed $eax def $rax
	movq	%rax, -8(%rbp)
	incq	(%rdi)
	cmpq	$0, -8(%rbp)
	jle	.LBB15_13
.LBB15_6:                               # %while.body
                                        # =>This Inner Loop Header: Depth=1
	movq	(%rdi), %r9
	movq	-8(%rbp), %rax
	movq	%rax, %rdx
	shrq	$32, %rdx
	je	.LBB15_7
# %bb.8:                                #   in Loop: Header=BB15_6 Depth=1
	cqto
	idivq	%r8
	jmp	.LBB15_9
	.p2align	4, 0x90
.LBB15_7:                               #   in Loop: Header=BB15_6 Depth=1
                                        # kill: def $eax killed $eax killed $rax
	xorl	%edx, %edx
	divl	%r8d
                                        # kill: def $edx killed $edx def $rdx
.LBB15_9:                               #   in Loop: Header=BB15_6 Depth=1
	addb	$48, %dl
	movb	%dl, (%rcx,%r9)
	movq	-8(%rbp), %rax
	movq	%rax, %rdx
	shrq	$32, %rdx
	je	.LBB15_10
# %bb.11:                               #   in Loop: Header=BB15_6 Depth=1
	cqto
	idivq	%r8
	movq	%rax, -8(%rbp)
	incq	(%rdi)
	cmpq	$0, -8(%rbp)
	jg	.LBB15_6
.LBB15_13:                              # %while.end
	movq	%rsp, %rdx
	leaq	-16(%rdx), %rax
	movq	%rax, %rsp
	movq	$0, -16(%rdx)
	cmpq	$1, (%rsi)
	jne	.LBB15_15
# %bb.14:                               # %then.2
	movq	-16(%rbp), %rdx
	movb	$45, (%rdx)
	movq	$1, (%rax)
.LBB15_15:                              # %ifcont.2
	movq	%rsp, %rsi
	leaq	-16(%rsi), %rdx
	movq	%rdx, %rsp
	movq	(%rdi), %rdi
	decq	%rdi
	movq	%rdi, -16(%rsi)
	cmpq	$0, (%rdx)
	js	.LBB15_18
	.p2align	4, 0x90
.LBB15_17:                              # %while.body.1
                                        # =>This Inner Loop Header: Depth=1
	movslq	(%rdx), %rsi
	movzbl	(%rcx,%rsi), %esi
	movq	-16(%rbp), %rdi
	movq	(%rax), %r8
	movb	%sil, (%rdi,%r8)
	incq	(%rax)
	decq	(%rdx)
	cmpq	$0, (%rdx)
	jns	.LBB15_17
.LBB15_18:                              # %while.end.1
	movq	-16(%rbp), %rcx
	movq	(%rax), %rdx
	movb	$0, (%rcx,%rdx)
	movq	(%rax), %rax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end15:
	.size	i64str__2__i64__byte_ptr1__ret_i64, .Lfunc_end15-i64str__2__i64__byte_ptr1__ret_i64
	.cfi_endproc
                                        # -- End function
	.globl	u32str__2__u32__byte_ptr1__ret_u32 # -- Begin function u32str__2__u32__byte_ptr1__ret_u32
	.p2align	4, 0x90
	.type	u32str__2__u32__byte_ptr1__ret_u32,@function
u32str__2__u32__byte_ptr1__ret_u32:     # @u32str__2__u32__byte_ptr1__ret_u32
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	subq	$16, %rsp
	movl	%edi, -4(%rbp)
	movq	%rsi, -16(%rbp)
	testl	%edi, %edi
	je	.LBB16_1
# %bb.2:                                # %else
	movq	%rsp, %rax
	leaq	-16(%rax), %rcx
	movq	%rcx, %rsp
	movl	$0, -16(%rax)
	movq	%rsp, %rax
	addq	$-32, %rax
	movq	%rax, %rsp
	cmpl	$0, -4(%rbp)
	jle	.LBB16_5
	.p2align	4, 0x90
.LBB16_4:                               # %while.body
                                        # =>This Inner Loop Header: Depth=1
	movslq	-4(%rbp), %rdx
	imulq	$1717986919, %rdx, %rsi         # imm = 0x66666667
	movq	%rsi, %rdi
	shrq	$63, %rdi
	shrq	$34, %rsi
	addl	%edi, %esi
	addl	%esi, %esi
	leal	(%rsi,%rsi,4), %esi
	subl	%esi, %edx
	addb	$48, %dl
	movslq	(%rcx), %rsi
	movb	%dl, (%rax,%rsi)
	movslq	-4(%rbp), %rdx
	imulq	$1717986919, %rdx, %rdx         # imm = 0x66666667
	movq	%rdx, %rsi
	shrq	$63, %rsi
	sarq	$34, %rdx
	addl	%esi, %edx
	movl	%edx, -4(%rbp)
	incl	(%rcx)
	cmpl	$0, -4(%rbp)
	jg	.LBB16_4
.LBB16_5:                               # %while.end
	movq	%rsp, %rsi
	leaq	-16(%rsi), %rdx
	movq	%rdx, %rsp
	movl	$0, -16(%rsi)
	movq	%rsp, %rdi
	leaq	-16(%rdi), %rsi
	movq	%rsi, %rsp
	movl	(%rcx), %ecx
	decl	%ecx
	movl	%ecx, -16(%rdi)
	cmpl	$0, (%rsi)
	js	.LBB16_8
	.p2align	4, 0x90
.LBB16_7:                               # %while.body.1
                                        # =>This Inner Loop Header: Depth=1
	movslq	(%rsi), %rcx
	movzbl	(%rax,%rcx), %ecx
	movq	-16(%rbp), %rdi
	movslq	(%rdx), %r8
	movb	%cl, (%rdi,%r8)
	incl	(%rdx)
	decl	(%rsi)
	cmpl	$0, (%rsi)
	jns	.LBB16_7
.LBB16_8:                               # %while.end.1
	movq	-16(%rbp), %rax
	movslq	(%rdx), %rcx
	movb	$0, (%rax,%rcx)
	movl	(%rdx), %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB16_1:                               # %then
	.cfi_def_cfa %rbp, 16
	movq	-16(%rbp), %rax
	movb	$48, (%rax)
	movq	-16(%rbp), %rax
	movb	$0, 1(%rax)
	movl	$1, %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end16:
	.size	u32str__2__u32__byte_ptr1__ret_u32, .Lfunc_end16-u32str__2__u32__byte_ptr1__ret_u32
	.cfi_endproc
                                        # -- End function
	.globl	u64str__2__u64__byte_ptr1__ret_u64 # -- Begin function u64str__2__u64__byte_ptr1__ret_u64
	.p2align	4, 0x90
	.type	u64str__2__u64__byte_ptr1__ret_u64,@function
u64str__2__u64__byte_ptr1__ret_u64:     # @u64str__2__u64__byte_ptr1__ret_u64
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	subq	$16, %rsp
	movq	%rdi, -8(%rbp)
	movq	%rsi, -16(%rbp)
	testq	%rdi, %rdi
	jne	.LBB17_2
# %bb.1:                                # %then
	movq	-16(%rbp), %rax
	movb	$48, (%rax)
	movq	-16(%rbp), %rax
	movb	$0, 1(%rax)
	movl	$1, %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB17_2:                               # %else
	.cfi_def_cfa %rbp, 16
	movq	%rsp, %rax
	leaq	-16(%rax), %rsi
	movq	%rsi, %rsp
	movq	$0, -16(%rax)
	movq	%rsp, %rcx
	addq	$-32, %rcx
	movq	%rcx, %rsp
	movl	$10, %edi
	cmpq	$0, -8(%rbp)
	jne	.LBB17_4
	jmp	.LBB17_11
	.p2align	4, 0x90
.LBB17_8:                               #   in Loop: Header=BB17_4 Depth=1
                                        # kill: def $eax killed $eax killed $rax
	xorl	%edx, %edx
	divl	%edi
                                        # kill: def $eax killed $eax def $rax
	movq	%rax, -8(%rbp)
	incq	(%rsi)
	cmpq	$0, -8(%rbp)
	je	.LBB17_11
.LBB17_4:                               # %while.body
                                        # =>This Inner Loop Header: Depth=1
	movq	(%rsi), %r8
	movq	-8(%rbp), %rax
	movq	%rax, %rdx
	shrq	$32, %rdx
	je	.LBB17_5
# %bb.6:                                #   in Loop: Header=BB17_4 Depth=1
	cqto
	idivq	%rdi
	jmp	.LBB17_7
	.p2align	4, 0x90
.LBB17_5:                               #   in Loop: Header=BB17_4 Depth=1
                                        # kill: def $eax killed $eax killed $rax
	xorl	%edx, %edx
	divl	%edi
                                        # kill: def $edx killed $edx def $rdx
.LBB17_7:                               #   in Loop: Header=BB17_4 Depth=1
	addb	$48, %dl
	movb	%dl, (%rcx,%r8)
	movq	-8(%rbp), %rax
	movq	%rax, %rdx
	shrq	$32, %rdx
	je	.LBB17_8
# %bb.9:                                #   in Loop: Header=BB17_4 Depth=1
	cqto
	idivq	%rdi
	movq	%rax, -8(%rbp)
	incq	(%rsi)
	cmpq	$0, -8(%rbp)
	jne	.LBB17_4
.LBB17_11:                              # %while.end
	movq	%rsp, %rdx
	leaq	-16(%rdx), %rax
	movq	%rax, %rsp
	movq	$0, -16(%rdx)
	movq	%rsp, %rdi
	leaq	-16(%rdi), %rdx
	movq	%rdx, %rsp
	movq	(%rsi), %rsi
	movq	%rsi, -16(%rdi)
	cmpq	$0, (%rdx)
	je	.LBB17_14
	.p2align	4, 0x90
.LBB17_13:                              # %while.body.1
                                        # =>This Inner Loop Header: Depth=1
	movq	(%rdx), %rsi
	decq	%rsi
	movq	%rsi, (%rdx)
	movslq	%esi, %rsi
	movzbl	(%rcx,%rsi), %esi
	movq	-16(%rbp), %rdi
	movq	(%rax), %r8
	movb	%sil, (%rdi,%r8)
	incq	(%rax)
	cmpq	$0, (%rdx)
	jne	.LBB17_13
.LBB17_14:                              # %while.end.1
	movq	-16(%rbp), %rcx
	movq	(%rax), %rdx
	movb	$0, (%rcx,%rdx)
	movq	(%rax), %rax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end17:
	.size	u64str__2__u64__byte_ptr1__ret_u64, .Lfunc_end17-u64str__2__u64__byte_ptr1__ret_u64
	.cfi_endproc
                                        # -- End function
	.globl	str2i32__1__byte_ptr1__ret_int  # -- Begin function str2i32__1__byte_ptr1__ret_int
	.p2align	4, 0x90
	.type	str2i32__1__byte_ptr1__ret_int,@function
str2i32__1__byte_ptr1__ret_int:         # @str2i32__1__byte_ptr1__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	subq	$32, %rsp
	movq	%rdi, -16(%rbp)
	movl	$0, -8(%rbp)
	movl	$1, -20(%rbp)
	movl	$0, -4(%rbp)
	jmp	.LBB18_1
	.p2align	4, 0x90
.LBB18_5:                               # %while.body
                                        #   in Loop: Header=BB18_1 Depth=1
	incl	-4(%rbp)
.LBB18_1:                               # %while.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	-16(%rbp), %rax
	movslq	-4(%rbp), %rcx
	movzbl	(%rax,%rcx), %eax
	cmpl	$32, %eax
	je	.LBB18_5
# %bb.2:                                # %while.cond
                                        #   in Loop: Header=BB18_1 Depth=1
	cmpl	$9, %eax
	je	.LBB18_5
# %bb.3:                                # %while.cond
                                        #   in Loop: Header=BB18_1 Depth=1
	cmpl	$10, %eax
	je	.LBB18_5
# %bb.4:                                # %while.cond
                                        #   in Loop: Header=BB18_1 Depth=1
	cmpl	$13, %eax
	je	.LBB18_5
# %bb.6:                                # %while.end
	movq	-16(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$45, (%rax,%rcx)
	jne	.LBB18_8
# %bb.7:                                # %then
	movl	$-1, -20(%rbp)
	jmp	.LBB18_9
.LBB18_8:                               # %else
	movq	-16(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$43, (%rax,%rcx)
	jne	.LBB18_10
.LBB18_9:                               # %elif_then_0
	incl	-4(%rbp)
.LBB18_10:                              # %while.cond.1
	movq	-16(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB18_13
# %bb.11:                               # %while.body.1
	movq	%rsp, %rdx
	leaq	-16(%rdx), %rax
	movq	%rax, %rsp
	movq	-16(%rbp), %rcx
	movslq	-4(%rbp), %rsi
	movzbl	(%rcx,%rsi), %ecx
	movb	%cl, -16(%rdx)
	cmpl	$48, %ecx
	jl	.LBB18_13
# %bb.12:                               # %while.body.1
	cmpl	$58, %ecx
	jge	.LBB18_13
# %bb.14:                               # %then.1
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rsp
	movzbl	(%rax), %eax
	leal	-48(%rax), %edx
	movl	%edx, -16(%rcx)
	movl	-8(%rbp), %ecx
	leal	(%rcx,%rcx,4), %ecx
	leal	(%rax,%rcx,2), %eax
	addl	$-48, %eax
	movl	%eax, -8(%rbp)
	jmp	.LBB18_9
.LBB18_13:                              # %while.end.1
	movl	-8(%rbp), %eax
	imull	-20(%rbp), %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end18:
	.size	str2i32__1__byte_ptr1__ret_int, .Lfunc_end18-str2i32__1__byte_ptr1__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	str2u32__1__byte_ptr1__ret_uint # -- Begin function str2u32__1__byte_ptr1__ret_uint
	.p2align	4, 0x90
	.type	str2u32__1__byte_ptr1__ret_uint,@function
str2u32__1__byte_ptr1__ret_uint:        # @str2u32__1__byte_ptr1__ret_uint
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	subq	$16, %rsp
	movq	%rdi, -16(%rbp)
	movl	$0, -8(%rbp)
	movl	$0, -4(%rbp)
	movb	$13, %al
	movb	$10, %cl
	movb	$9, %dl
	jmp	.LBB19_1
	.p2align	4, 0x90
.LBB19_5:                               # %while.body
                                        #   in Loop: Header=BB19_1 Depth=1
	incl	-4(%rbp)
.LBB19_1:                               # %while.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	-16(%rbp), %rsi
	movslq	-4(%rbp), %rdi
	movzbl	(%rsi,%rdi), %esi
	cmpb	$32, %sil
	je	.LBB19_5
# %bb.2:                                # %while.cond
                                        #   in Loop: Header=BB19_1 Depth=1
	cmpb	%dl, %sil
	je	.LBB19_5
# %bb.3:                                # %while.cond
                                        #   in Loop: Header=BB19_1 Depth=1
	cmpb	%cl, %sil
	je	.LBB19_5
# %bb.4:                                # %while.cond
                                        #   in Loop: Header=BB19_1 Depth=1
	cmpb	%al, %sil
	je	.LBB19_5
# %bb.6:                                # %while.end
	movq	-16(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$45, (%rax,%rcx)
	jne	.LBB19_9
# %bb.7:                                # %then
	xorl	%eax, %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB19_9:                               # %else
	.cfi_def_cfa %rbp, 16
	movq	-16(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$43, (%rax,%rcx)
	jne	.LBB19_11
.LBB19_10:                              # %elif_then_0
	incl	-4(%rbp)
.LBB19_11:                              # %while.cond.1
	movq	-16(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB19_14
# %bb.12:                               # %while.body.1
	movq	%rsp, %rdx
	leaq	-16(%rdx), %rax
	movq	%rax, %rsp
	movq	-16(%rbp), %rcx
	movslq	-4(%rbp), %rsi
	movzbl	(%rcx,%rsi), %ecx
	movb	%cl, -16(%rdx)
	cmpb	$48, %cl
	jl	.LBB19_14
# %bb.13:                               # %while.body.1
	movb	$57, %dl
	cmpb	%dl, %cl
	jg	.LBB19_14
# %bb.15:                               # %then.1
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rsp
	movzbl	(%rax), %eax
	addb	$-48, %al
	movzbl	%al, %eax
	movl	%eax, -16(%rcx)
	movl	-8(%rbp), %ecx
	leal	(%rcx,%rcx,4), %ecx
	leal	(%rax,%rcx,2), %eax
	movl	%eax, -8(%rbp)
	jmp	.LBB19_10
.LBB19_14:                              # %while.end.1
	movl	-8(%rbp), %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end19:
	.size	str2u32__1__byte_ptr1__ret_uint, .Lfunc_end19-str2u32__1__byte_ptr1__ret_uint
	.cfi_endproc
                                        # -- End function
	.globl	str2i64__1__byte_ptr1__ret_i64  # -- Begin function str2i64__1__byte_ptr1__ret_i64
	.p2align	4, 0x90
	.type	str2i64__1__byte_ptr1__ret_i64,@function
str2i64__1__byte_ptr1__ret_i64:         # @str2i64__1__byte_ptr1__ret_i64
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	subq	$32, %rsp
	movq	%rdi, -16(%rbp)
	movq	$0, -24(%rbp)
	movq	$1, -32(%rbp)
	movl	$0, -4(%rbp)
	movb	$13, %al
	movb	$10, %cl
	movb	$9, %dl
	jmp	.LBB20_1
	.p2align	4, 0x90
.LBB20_5:                               # %while.body
                                        #   in Loop: Header=BB20_1 Depth=1
	incl	-4(%rbp)
.LBB20_1:                               # %while.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	-16(%rbp), %rsi
	movslq	-4(%rbp), %rdi
	movzbl	(%rsi,%rdi), %esi
	cmpb	$32, %sil
	je	.LBB20_5
# %bb.2:                                # %while.cond
                                        #   in Loop: Header=BB20_1 Depth=1
	cmpb	%dl, %sil
	je	.LBB20_5
# %bb.3:                                # %while.cond
                                        #   in Loop: Header=BB20_1 Depth=1
	cmpb	%cl, %sil
	je	.LBB20_5
# %bb.4:                                # %while.cond
                                        #   in Loop: Header=BB20_1 Depth=1
	cmpb	%al, %sil
	je	.LBB20_5
# %bb.6:                                # %while.end
	movq	-16(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$45, (%rax,%rcx)
	jne	.LBB20_8
# %bb.7:                                # %then
	movq	$-1, -32(%rbp)
	jmp	.LBB20_9
.LBB20_8:                               # %else
	movq	-16(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$43, (%rax,%rcx)
	jne	.LBB20_10
.LBB20_9:                               # %elif_then_0
	incl	-4(%rbp)
.LBB20_10:                              # %while.cond.1
	movq	-16(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB20_13
# %bb.11:                               # %while.body.1
	movq	%rsp, %rdx
	leaq	-16(%rdx), %rax
	movq	%rax, %rsp
	movq	-16(%rbp), %rcx
	movslq	-4(%rbp), %rsi
	movzbl	(%rcx,%rsi), %ecx
	movb	%cl, -16(%rdx)
	cmpb	$48, %cl
	jl	.LBB20_13
# %bb.12:                               # %while.body.1
	movb	$57, %dl
	cmpb	%dl, %cl
	jg	.LBB20_13
# %bb.14:                               # %then.1
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rsp
	movzbl	(%rax), %eax
	addb	$-48, %al
	movsbq	%al, %rax
	movq	%rax, -16(%rcx)
	movq	-24(%rbp), %rcx
	leaq	(%rcx,%rcx,4), %rcx
	leaq	(%rax,%rcx,2), %rax
	movq	%rax, -24(%rbp)
	jmp	.LBB20_9
.LBB20_13:                              # %while.end.1
	movq	-24(%rbp), %rax
	imulq	-32(%rbp), %rax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end20:
	.size	str2i64__1__byte_ptr1__ret_i64, .Lfunc_end20-str2i64__1__byte_ptr1__ret_i64
	.cfi_endproc
                                        # -- End function
	.globl	str2u64__1__byte_ptr1__ret_u64  # -- Begin function str2u64__1__byte_ptr1__ret_u64
	.p2align	4, 0x90
	.type	str2u64__1__byte_ptr1__ret_u64,@function
str2u64__1__byte_ptr1__ret_u64:         # @str2u64__1__byte_ptr1__ret_u64
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	subq	$32, %rsp
	movq	%rdi, -16(%rbp)
	movq	$0, -24(%rbp)
	movl	$0, -4(%rbp)
	movb	$13, %al
	movb	$10, %cl
	movb	$9, %dl
	jmp	.LBB21_1
	.p2align	4, 0x90
.LBB21_5:                               # %while.body
                                        #   in Loop: Header=BB21_1 Depth=1
	incl	-4(%rbp)
.LBB21_1:                               # %while.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	-16(%rbp), %rsi
	movslq	-4(%rbp), %rdi
	movzbl	(%rsi,%rdi), %esi
	cmpb	$32, %sil
	je	.LBB21_5
# %bb.2:                                # %while.cond
                                        #   in Loop: Header=BB21_1 Depth=1
	cmpb	%dl, %sil
	je	.LBB21_5
# %bb.3:                                # %while.cond
                                        #   in Loop: Header=BB21_1 Depth=1
	cmpb	%cl, %sil
	je	.LBB21_5
# %bb.4:                                # %while.cond
                                        #   in Loop: Header=BB21_1 Depth=1
	cmpb	%al, %sil
	je	.LBB21_5
# %bb.6:                                # %while.end
	movq	-16(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$45, (%rax,%rcx)
	jne	.LBB21_9
# %bb.7:                                # %then
	xorl	%eax, %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB21_9:                               # %else
	.cfi_def_cfa %rbp, 16
	movq	-16(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$43, (%rax,%rcx)
	jne	.LBB21_11
.LBB21_10:                              # %elif_then_0
	incl	-4(%rbp)
.LBB21_11:                              # %while.cond.1
	movq	-16(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB21_14
# %bb.12:                               # %while.body.1
	movq	%rsp, %rdx
	leaq	-16(%rdx), %rax
	movq	%rax, %rsp
	movq	-16(%rbp), %rcx
	movslq	-4(%rbp), %rsi
	movzbl	(%rcx,%rsi), %ecx
	movb	%cl, -16(%rdx)
	cmpb	$48, %cl
	jl	.LBB21_14
# %bb.13:                               # %while.body.1
	movb	$57, %dl
	cmpb	%dl, %cl
	jg	.LBB21_14
# %bb.15:                               # %then.1
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rsp
	movzbl	(%rax), %eax
	addb	$-48, %al
	movzbl	%al, %eax
	movq	%rax, -16(%rcx)
	movq	-24(%rbp), %rcx
	leaq	(%rcx,%rcx,4), %rcx
	leaq	(%rax,%rcx,2), %rax
	movq	%rax, -24(%rbp)
	jmp	.LBB21_10
.LBB21_14:                              # %while.end.1
	movq	-24(%rbp), %rax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end21:
	.size	str2u64__1__byte_ptr1__ret_u64, .Lfunc_end21-str2u64__1__byte_ptr1__ret_u64
	.cfi_endproc
                                        # -- End function
	.section	.rodata.cst4,"aM",@progbits,4
	.p2align	2, 0x0                          # -- Begin function float2str__3__float__byte_ptr1__i32__ret_i32
.LCPI22_0:
	.long	0x3f000000                      # float 0.5
	.text
	.globl	float2str__3__float__byte_ptr1__i32__ret_i32
	.p2align	4, 0x90
	.type	float2str__3__float__byte_ptr1__i32__ret_i32,@function
float2str__3__float__byte_ptr1__i32__ret_i32: # @float2str__3__float__byte_ptr1__i32__ret_i32
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	subq	$32, %rsp
	vmovss	%xmm0, -20(%rbp)
	movq	%rdi, -16(%rbp)
	movl	%esi, -8(%rbp)
	movl	$0, -4(%rbp)
	vxorps	%xmm1, %xmm1, %xmm1
	vucomiss	%xmm0, %xmm1
	jbe	.LBB22_2
# %bb.1:                                # %then
	movq	-16(%rbp), %rax
	movb	$45, (%rax)
	movl	$1, -4(%rbp)
	vsubss	-20(%rbp), %xmm1, %xmm0
	vmovss	%xmm0, -20(%rbp)
.LBB22_2:                               # %ifcont
	vmovss	-20(%rbp), %xmm0                # xmm0 = mem[0],zero,zero,zero
	vucomiss	%xmm1, %xmm0
	jne	.LBB22_7
	jp	.LBB22_7
# %bb.3:                                # %then.1
	movq	-16(%rbp), %rax
	movslq	-4(%rbp), %rcx
	movb	$48, (%rax,%rcx)
	movq	-16(%rbp), %rax
	movl	-4(%rbp), %ecx
	incl	%ecx
	movslq	%ecx, %rcx
	movb	$46, (%rax,%rcx)
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rax
	movq	%rax, %rsp
	movl	$0, -16(%rcx)
	movl	(%rax), %ecx
	cmpl	-8(%rbp), %ecx
	jge	.LBB22_6
	.p2align	4, 0x90
.LBB22_5:                               # %while.body
                                        # =>This Inner Loop Header: Depth=1
	movq	-16(%rbp), %rcx
	movl	-4(%rbp), %edx
	movl	(%rax), %esi
	addl	%esi, %edx
	addl	$2, %edx
	movslq	%edx, %rdx
	movb	$48, (%rcx,%rdx)
	incl	(%rax)
	movl	(%rax), %ecx
	cmpl	-8(%rbp), %ecx
	jl	.LBB22_5
.LBB22_6:                               # %while.end
	movq	-16(%rbp), %rax
	movl	-4(%rbp), %ecx
	movl	-8(%rbp), %edx
	addl	%edx, %ecx
	addl	$2, %ecx
	movslq	%ecx, %rcx
	movb	$0, (%rax,%rcx)
	movl	-4(%rbp), %eax
	movl	-8(%rbp), %ecx
	leal	1(%rax,%rcx), %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB22_7:                               # %else.1
	.cfi_def_cfa %rbp, 16
	movq	%rsp, %rdx
	leaq	-16(%rdx), %rcx
	movq	%rcx, %rsp
	vcvttss2si	-20(%rbp), %eax
	movl	%eax, -16(%rdx)
	movq	%rsp, %rsi
	leaq	-16(%rsi), %rax
	movq	%rax, %rsp
	vmovss	-20(%rbp), %xmm0                # xmm0 = mem[0],zero,zero,zero
	vcvtsi2ssl	-16(%rdx), %xmm2, %xmm1
	vsubss	%xmm1, %xmm0, %xmm0
	vmovss	%xmm0, -16(%rsi)
	movq	%rsp, %rsi
	leaq	-16(%rsi), %rdx
	movq	%rdx, %rsp
	movl	$1, -16(%rsi)
	movq	%rsp, %rdi
	leaq	-16(%rdi), %rsi
	movq	%rsi, %rsp
	movl	$0, -16(%rdi)
	movl	(%rsi), %edi
	cmpl	-8(%rbp), %edi
	jge	.LBB22_10
	.p2align	4, 0x90
.LBB22_9:                               # %while.body.1
                                        # =>This Inner Loop Header: Depth=1
	movl	(%rdx), %edi
	addl	%edi, %edi
	leal	(%rdi,%rdi,4), %edi
	movl	%edi, (%rdx)
	incl	(%rsi)
	movl	(%rsi), %edi
	cmpl	-8(%rbp), %edi
	jl	.LBB22_9
.LBB22_10:                              # %while.end.1
	movq	%rsp, %rsi
	leaq	-16(%rsi), %rsp
	vcvtsi2ssl	(%rdx), %xmm2, %xmm0
	vmulss	(%rax), %xmm0, %xmm0
	vmovss	%xmm0, -16(%rsi)
	movq	%rsp, %rdi
	leaq	-16(%rdi), %rax
	movq	%rax, %rsp
	vmovss	-16(%rsi), %xmm0                # xmm0 = mem[0],zero,zero,zero
	vaddss	.LCPI22_0(%rip), %xmm0, %xmm0
	vcvttss2si	%xmm0, %esi
	movl	%esi, -16(%rdi)
	cmpl	(%rdx), %esi
	jl	.LBB22_12
# %bb.11:                               # %then.2
	incl	(%rcx)
	movl	$0, (%rax)
.LBB22_12:                              # %ifcont.2
	cmpl	$0, (%rcx)
	je	.LBB22_13
# %bb.19:                               # %else.4
	movq	%rsp, %rdx
	addq	$-32, %rdx
	movq	%rdx, %rsp
	movq	%rsp, %rdi
	leaq	-16(%rdi), %rsi
	movq	%rsi, %rsp
	movl	$0, -16(%rdi)
	movq	%rsp, %r8
	leaq	-16(%r8), %rdi
	movq	%rdi, %rsp
	movl	(%rcx), %ecx
	movl	%ecx, -16(%r8)
	cmpl	$0, (%rdi)
	jle	.LBB22_22
	.p2align	4, 0x90
.LBB22_21:                              # %while.body.2
                                        # =>This Inner Loop Header: Depth=1
	movslq	(%rdi), %rcx
	imulq	$1717986919, %rcx, %r8          # imm = 0x66666667
	movq	%r8, %r9
	shrq	$63, %r9
	shrq	$34, %r8
	addl	%r9d, %r8d
	addl	%r8d, %r8d
	leal	(%r8,%r8,4), %r8d
	subl	%r8d, %ecx
	addb	$48, %cl
	movslq	(%rsi), %r8
	movb	%cl, (%rdx,%r8)
	movslq	(%rdi), %rcx
	imulq	$1717986919, %rcx, %rcx         # imm = 0x66666667
	movq	%rcx, %r8
	shrq	$63, %r8
	sarq	$34, %rcx
	addl	%r8d, %ecx
	movl	%ecx, (%rdi)
	incl	(%rsi)
	cmpl	$0, (%rdi)
	jg	.LBB22_21
.LBB22_22:                              # %while.end.2
	movq	%rsp, %rdi
	leaq	-16(%rdi), %rcx
	movq	%rcx, %rsp
	movl	(%rsi), %esi
	decl	%esi
	movl	%esi, -16(%rdi)
	cmpl	$0, (%rcx)
	js	.LBB22_14
	.p2align	4, 0x90
.LBB22_24:                              # %while.body.3
                                        # =>This Inner Loop Header: Depth=1
	movslq	(%rcx), %rsi
	movzbl	(%rdx,%rsi), %esi
	movq	-16(%rbp), %rdi
	movslq	-4(%rbp), %r8
	movb	%sil, (%rdi,%r8)
	incl	-4(%rbp)
	decl	(%rcx)
	cmpl	$0, (%rcx)
	jns	.LBB22_24
.LBB22_14:                              # %ifcont.4
	cmpl	$0, -8(%rbp)
	jg	.LBB22_15
	jmp	.LBB22_25
.LBB22_13:                              # %then.4
	movq	-16(%rbp), %rcx
	movslq	-4(%rbp), %rdx
	movb	$48, (%rcx,%rdx)
	incl	-4(%rbp)
	cmpl	$0, -8(%rbp)
	jle	.LBB22_25
.LBB22_15:                              # %then.5
	movq	-16(%rbp), %rcx
	movslq	-4(%rbp), %rdx
	movb	$46, (%rcx,%rdx)
	incl	-4(%rbp)
	cmpl	$0, (%rax)
	je	.LBB22_16
# %bb.27:                               # %else.6
	movq	%rsp, %rcx
	addq	$-32, %rcx
	movq	%rcx, %rsp
	movq	%rsp, %rsi
	leaq	-16(%rsi), %rdx
	movq	%rdx, %rsp
	movl	$0, -16(%rsi)
	movq	%rsp, %rdi
	leaq	-16(%rdi), %rsi
	movq	%rsi, %rsp
	movl	(%rax), %eax
	movl	%eax, -16(%rdi)
	cmpl	$0, (%rsi)
	jle	.LBB22_30
	.p2align	4, 0x90
.LBB22_29:                              # %while.body.5
                                        # =>This Inner Loop Header: Depth=1
	movslq	(%rsi), %rax
	imulq	$1717986919, %rax, %rdi         # imm = 0x66666667
	movq	%rdi, %r8
	shrq	$63, %r8
	shrq	$34, %rdi
	addl	%r8d, %edi
	addl	%edi, %edi
	leal	(%rdi,%rdi,4), %edi
	subl	%edi, %eax
	addb	$48, %al
	movslq	(%rdx), %rdi
	movb	%al, (%rcx,%rdi)
	movslq	(%rsi), %rax
	imulq	$1717986919, %rax, %rax         # imm = 0x66666667
	movq	%rax, %rdi
	shrq	$63, %rdi
	sarq	$34, %rax
	addl	%edi, %eax
	movl	%eax, (%rsi)
	incl	(%rdx)
	cmpl	$0, (%rsi)
	jg	.LBB22_29
.LBB22_30:                              # %while.end.5
	movq	%rsp, %rsi
	leaq	-16(%rsi), %rax
	movq	%rax, %rsp
	movl	-8(%rbp), %edi
	subl	(%rdx), %edi
	movl	%edi, -16(%rsi)
	movq	%rsp, %rdi
	leaq	-16(%rdi), %rsi
	movq	%rsi, %rsp
	movl	$0, -16(%rdi)
	movl	(%rsi), %edi
	cmpl	(%rax), %edi
	jge	.LBB22_33
	.p2align	4, 0x90
.LBB22_32:                              # %while.body.6
                                        # =>This Inner Loop Header: Depth=1
	movq	-16(%rbp), %rdi
	movslq	-4(%rbp), %r8
	movb	$48, (%rdi,%r8)
	incl	-4(%rbp)
	incl	(%rsi)
	movl	(%rsi), %edi
	cmpl	(%rax), %edi
	jl	.LBB22_32
.LBB22_33:                              # %while.end.6
	movq	%rsp, %rsi
	leaq	-16(%rsi), %rax
	movq	%rax, %rsp
	movl	(%rdx), %edx
	decl	%edx
	movl	%edx, -16(%rsi)
	cmpl	$0, (%rax)
	js	.LBB22_25
	.p2align	4, 0x90
.LBB22_35:                              # %while.body.7
                                        # =>This Inner Loop Header: Depth=1
	movslq	(%rax), %rdx
	movzbl	(%rcx,%rdx), %edx
	movq	-16(%rbp), %rsi
	movslq	-4(%rbp), %rdi
	movb	%dl, (%rsi,%rdi)
	incl	-4(%rbp)
	decl	(%rax)
	cmpl	$0, (%rax)
	jns	.LBB22_35
.LBB22_25:                              # %ifcont.5
	movq	-16(%rbp), %rax
	movslq	-4(%rbp), %rcx
	movb	$0, (%rax,%rcx)
	movl	-4(%rbp), %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB22_16:                              # %then.6
	.cfi_def_cfa %rbp, 16
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rax
	movq	%rax, %rsp
	movl	$0, -16(%rcx)
	movl	(%rax), %ecx
	cmpl	-8(%rbp), %ecx
	jge	.LBB22_25
	.p2align	4, 0x90
.LBB22_18:                              # %while.body.4
                                        # =>This Inner Loop Header: Depth=1
	movq	-16(%rbp), %rcx
	movslq	-4(%rbp), %rdx
	movb	$48, (%rcx,%rdx)
	incl	-4(%rbp)
	incl	(%rax)
	movl	(%rax), %ecx
	cmpl	-8(%rbp), %ecx
	jl	.LBB22_18
	jmp	.LBB22_25
.Lfunc_end22:
	.size	float2str__3__float__byte_ptr1__i32__ret_i32, .Lfunc_end22-float2str__3__float__byte_ptr1__i32__ret_i32
	.cfi_endproc
                                        # -- End function
	.globl	is_whitespace__1__char__ret_bool # -- Begin function is_whitespace__1__char__ret_bool
	.p2align	4, 0x90
	.type	is_whitespace__1__char__ret_bool,@function
is_whitespace__1__char__ret_bool:       # @is_whitespace__1__char__ret_bool
	.cfi_startproc
# %bb.0:                                # %entry
	movb	%dil, -1(%rsp)
	cmpb	$32, %dil
	sete	%al
	cmpb	$9, %dil
	sete	%cl
	orb	%al, %cl
	cmpb	$10, %dil
	sete	%dl
	cmpb	$13, %dil
	sete	%al
	orb	%dl, %al
	orb	%cl, %al
	retq
.Lfunc_end23:
	.size	is_whitespace__1__char__ret_bool, .Lfunc_end23-is_whitespace__1__char__ret_bool
	.cfi_endproc
                                        # -- End function
	.globl	is_digit__1__char__ret_bool     # -- Begin function is_digit__1__char__ret_bool
	.p2align	4, 0x90
	.type	is_digit__1__char__ret_bool,@function
is_digit__1__char__ret_bool:            # @is_digit__1__char__ret_bool
	.cfi_startproc
# %bb.0:                                # %entry
	movb	%dil, -1(%rsp)
	cmpb	$48, %dil
	setge	%cl
	cmpb	$58, %dil
	setl	%al
	andb	%cl, %al
	retq
.Lfunc_end24:
	.size	is_digit__1__char__ret_bool, .Lfunc_end24-is_digit__1__char__ret_bool
	.cfi_endproc
                                        # -- End function
	.globl	is_alpha__1__char__ret_bool     # -- Begin function is_alpha__1__char__ret_bool
	.p2align	4, 0x90
	.type	is_alpha__1__char__ret_bool,@function
is_alpha__1__char__ret_bool:            # @is_alpha__1__char__ret_bool
	.cfi_startproc
# %bb.0:                                # %entry
	movb	%dil, -1(%rsp)
	cmpb	$97, %dil
	setge	%al
	cmpb	$123, %dil
	setl	%cl
	andb	%al, %cl
	cmpb	$65, %dil
	setge	%dl
	cmpb	$91, %dil
	setl	%al
	andb	%dl, %al
	orb	%cl, %al
	retq
.Lfunc_end25:
	.size	is_alpha__1__char__ret_bool, .Lfunc_end25-is_alpha__1__char__ret_bool
	.cfi_endproc
                                        # -- End function
	.globl	is_alnum__1__char__ret_bool     # -- Begin function is_alnum__1__char__ret_bool
	.p2align	4, 0x90
	.type	is_alnum__1__char__ret_bool,@function
is_alnum__1__char__ret_bool:            # @is_alnum__1__char__ret_bool
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbx
	.cfi_def_cfa_offset 16
	subq	$16, %rsp
	.cfi_def_cfa_offset 32
	.cfi_offset %rbx, -16
	movb	%dil, 15(%rsp)
	callq	is_alpha__1__char__ret_bool@PLT
	movl	%eax, %ebx
	movzbl	15(%rsp), %edi
	callq	is_digit__1__char__ret_bool@PLT
	orb	%bl, %al
	addq	$16, %rsp
	.cfi_def_cfa_offset 16
	popq	%rbx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end26:
	.size	is_alnum__1__char__ret_bool, .Lfunc_end26-is_alnum__1__char__ret_bool
	.cfi_endproc
                                        # -- End function
	.globl	is_hex_digit__1__char__ret_bool # -- Begin function is_hex_digit__1__char__ret_bool
	.p2align	4, 0x90
	.type	is_hex_digit__1__char__ret_bool,@function
is_hex_digit__1__char__ret_bool:        # @is_hex_digit__1__char__ret_bool
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rax
	.cfi_def_cfa_offset 16
	movb	%dil, 7(%rsp)
	callq	is_digit__1__char__ret_bool@PLT
	movzbl	7(%rsp), %ecx
	cmpb	$97, %cl
	setge	%dl
	cmpb	$103, %cl
	setl	%sil
	andb	%dl, %sil
	orb	%sil, %al
	cmpb	$65, %cl
	setge	%dl
	cmpb	$71, %cl
	setl	%cl
	andb	%dl, %cl
	orb	%cl, %al
	popq	%rcx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end27:
	.size	is_hex_digit__1__char__ret_bool, .Lfunc_end27-is_hex_digit__1__char__ret_bool
	.cfi_endproc
                                        # -- End function
	.globl	is_identifier_start__1__char__ret_bool # -- Begin function is_identifier_start__1__char__ret_bool
	.p2align	4, 0x90
	.type	is_identifier_start__1__char__ret_bool,@function
is_identifier_start__1__char__ret_bool: # @is_identifier_start__1__char__ret_bool
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rax
	.cfi_def_cfa_offset 16
	movb	%dil, 7(%rsp)
	callq	is_alpha__1__char__ret_bool@PLT
	cmpb	$95, 7(%rsp)
	sete	%cl
	orb	%cl, %al
	popq	%rcx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end28:
	.size	is_identifier_start__1__char__ret_bool, .Lfunc_end28-is_identifier_start__1__char__ret_bool
	.cfi_endproc
                                        # -- End function
	.globl	is_identifier_char__1__char__ret_bool # -- Begin function is_identifier_char__1__char__ret_bool
	.p2align	4, 0x90
	.type	is_identifier_char__1__char__ret_bool,@function
is_identifier_char__1__char__ret_bool:  # @is_identifier_char__1__char__ret_bool
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rax
	.cfi_def_cfa_offset 16
	movb	%dil, 7(%rsp)
	callq	is_alnum__1__char__ret_bool@PLT
	cmpb	$95, 7(%rsp)
	sete	%cl
	orb	%cl, %al
	popq	%rcx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end29:
	.size	is_identifier_char__1__char__ret_bool, .Lfunc_end29-is_identifier_char__1__char__ret_bool
	.cfi_endproc
                                        # -- End function
	.globl	is_newline__1__char__ret_bool   # -- Begin function is_newline__1__char__ret_bool
	.p2align	4, 0x90
	.type	is_newline__1__char__ret_bool,@function
is_newline__1__char__ret_bool:          # @is_newline__1__char__ret_bool
	.cfi_startproc
# %bb.0:                                # %entry
	movb	%dil, -1(%rsp)
	cmpb	$10, %dil
	sete	%cl
	cmpb	$13, %dil
	sete	%al
	orb	%cl, %al
	retq
.Lfunc_end30:
	.size	is_newline__1__char__ret_bool, .Lfunc_end30-is_newline__1__char__ret_bool
	.cfi_endproc
                                        # -- End function
	.globl	to_lower__1__char__ret_char     # -- Begin function to_lower__1__char__ret_char
	.p2align	4, 0x90
	.type	to_lower__1__char__ret_char,@function
to_lower__1__char__ret_char:            # @to_lower__1__char__ret_char
	.cfi_startproc
# %bb.0:                                # %entry
	movb	%dil, -1(%rsp)
	cmpb	$65, %dil
	jl	.LBB31_3
# %bb.1:                                # %entry
	cmpb	$90, %dil
	jg	.LBB31_3
# %bb.2:                                # %then
	movzbl	-1(%rsp), %eax
	addb	$32, %al
	retq
.LBB31_3:                               # %else
	movzbl	-1(%rsp), %eax
	retq
.Lfunc_end31:
	.size	to_lower__1__char__ret_char, .Lfunc_end31-to_lower__1__char__ret_char
	.cfi_endproc
                                        # -- End function
	.globl	to_upper__1__char__ret_char     # -- Begin function to_upper__1__char__ret_char
	.p2align	4, 0x90
	.type	to_upper__1__char__ret_char,@function
to_upper__1__char__ret_char:            # @to_upper__1__char__ret_char
	.cfi_startproc
# %bb.0:                                # %entry
	movb	%dil, -1(%rsp)
	cmpb	$97, %dil
	jl	.LBB32_3
# %bb.1:                                # %entry
	cmpb	$122, %dil
	jg	.LBB32_3
# %bb.2:                                # %then
	movzbl	-1(%rsp), %eax
	addb	$-32, %al
	retq
.LBB32_3:                               # %else
	movzbl	-1(%rsp), %eax
	retq
.Lfunc_end32:
	.size	to_upper__1__char__ret_char, .Lfunc_end32-to_upper__1__char__ret_char
	.cfi_endproc
                                        # -- End function
	.globl	char_to_digit__1__char__ret_int # -- Begin function char_to_digit__1__char__ret_int
	.p2align	4, 0x90
	.type	char_to_digit__1__char__ret_int,@function
char_to_digit__1__char__ret_int:        # @char_to_digit__1__char__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	movb	%dil, -1(%rsp)
	cmpb	$48, %dil
	jl	.LBB33_3
# %bb.1:                                # %entry
	cmpb	$57, %dil
	jg	.LBB33_3
# %bb.2:                                # %then
	movzbl	-1(%rsp), %eax
	addb	$-48, %al
	movsbl	%al, %eax
	retq
.LBB33_3:                               # %else
	movl	$-1, %eax
	retq
.Lfunc_end33:
	.size	char_to_digit__1__char__ret_int, .Lfunc_end33-char_to_digit__1__char__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	hex_to_int__1__char__ret_int    # -- Begin function hex_to_int__1__char__ret_int
	.p2align	4, 0x90
	.type	hex_to_int__1__char__ret_int,@function
hex_to_int__1__char__ret_int:           # @hex_to_int__1__char__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	movb	%dil, -1(%rsp)
	cmpb	$48, %dil
	jl	.LBB34_2
# %bb.1:                                # %entry
	cmpb	$57, %dil
	jg	.LBB34_2
# %bb.10:                               # %then
	movzbl	-1(%rsp), %eax
	addb	$-48, %al
	movsbl	%al, %eax
	retq
.LBB34_2:                               # %else
	movzbl	-1(%rsp), %eax
	cmpb	$97, %al
	jl	.LBB34_6
# %bb.3:                                # %else
	cmpb	$102, %al
	jg	.LBB34_6
# %bb.4:                                # %then.1
	movzbl	-1(%rsp), %eax
	addb	$-97, %al
	movzbl	%al, %eax
	addl	$10, %eax
	retq
.LBB34_6:                               # %else.1
	movzbl	-1(%rsp), %eax
	cmpb	$65, %al
	jl	.LBB34_9
# %bb.7:                                # %else.1
	cmpb	$70, %al
	jg	.LBB34_9
# %bb.8:                                # %then.2
	movzbl	-1(%rsp), %eax
	addb	$-65, %al
	movzbl	%al, %eax
	addl	$10, %eax
	retq
.LBB34_9:                               # %else.2
	movl	$-1, %eax
	retq
.Lfunc_end34:
	.size	hex_to_int__1__char__ret_int, .Lfunc_end34-hex_to_int__1__char__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	find_char__3__byte_ptr1__char__int__ret_int # -- Begin function find_char__3__byte_ptr1__char__int__ret_int
	.p2align	4, 0x90
	.type	find_char__3__byte_ptr1__char__int__ret_int,@function
find_char__3__byte_ptr1__char__int__ret_int: # @find_char__3__byte_ptr1__char__int__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	movq	%rdi, -16(%rsp)
	movb	%sil, -21(%rsp)
	movl	%edx, -4(%rsp)
	movl	%edx, -20(%rsp)
	movq	-16(%rsp), %rax
	movslq	-20(%rsp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB35_4
	.p2align	4, 0x90
.LBB35_2:                               # %for.body
                                        # =>This Inner Loop Header: Depth=1
	movq	-16(%rsp), %rax
	movslq	-20(%rsp), %rcx
	movzbl	(%rax,%rcx), %eax
	cmpb	-21(%rsp), %al
	je	.LBB35_5
# %bb.3:                                # %else
                                        #   in Loop: Header=BB35_2 Depth=1
	incl	-20(%rsp)
	movq	-16(%rsp), %rax
	movslq	-20(%rsp), %rcx
	cmpb	$0, (%rax,%rcx)
	jne	.LBB35_2
.LBB35_4:                               # %for.end
	movl	$-1, %eax
	retq
.LBB35_5:                               # %then
	movl	-20(%rsp), %eax
	retq
.Lfunc_end35:
	.size	find_char__3__byte_ptr1__char__int__ret_int, .Lfunc_end35-find_char__3__byte_ptr1__char__int__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	find_char_last__2__byte_ptr1__char__ret_int # -- Begin function find_char_last__2__byte_ptr1__char__ret_int
	.p2align	4, 0x90
	.type	find_char_last__2__byte_ptr1__char__ret_int,@function
find_char_last__2__byte_ptr1__char__ret_int: # @find_char_last__2__byte_ptr1__char__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	movq	%rdi, -8(%rsp)
	movb	%sil, -17(%rsp)
	movl	$-1, -12(%rsp)
	movl	$0, -16(%rsp)
	jmp	.LBB36_1
	.p2align	4, 0x90
.LBB36_4:                               # %ifcont
                                        #   in Loop: Header=BB36_1 Depth=1
	incl	-16(%rsp)
.LBB36_1:                               # %for.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	-8(%rsp), %rax
	movslq	-16(%rsp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB36_5
# %bb.2:                                # %for.body
                                        #   in Loop: Header=BB36_1 Depth=1
	movq	-8(%rsp), %rax
	movslq	-16(%rsp), %rcx
	movzbl	(%rax,%rcx), %eax
	cmpb	-17(%rsp), %al
	jne	.LBB36_4
# %bb.3:                                # %then
                                        #   in Loop: Header=BB36_1 Depth=1
	movl	-16(%rsp), %eax
	movl	%eax, -12(%rsp)
	jmp	.LBB36_4
.LBB36_5:                               # %for.end
	movl	-12(%rsp), %eax
	retq
.Lfunc_end36:
	.size	find_char_last__2__byte_ptr1__char__ret_int, .Lfunc_end36-find_char_last__2__byte_ptr1__char__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	find_any__3__byte_ptr1__byte_ptr1__int__ret_int # -- Begin function find_any__3__byte_ptr1__byte_ptr1__int__ret_int
	.p2align	4, 0x90
	.type	find_any__3__byte_ptr1__byte_ptr1__int__ret_int,@function
find_any__3__byte_ptr1__byte_ptr1__int__ret_int: # @find_any__3__byte_ptr1__byte_ptr1__int__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	subq	$32, %rsp
	movq	%rdi, -24(%rbp)
	movq	%rsi, -16(%rbp)
	movl	%edx, -28(%rbp)
	movl	%edx, -4(%rbp)
	movq	-24(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB37_6
.LBB37_2:                               # %for.body
                                        # =>This Loop Header: Depth=1
                                        #     Child Loop BB37_4 Depth 2
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rax
	movq	%rax, %rsp
	movl	$0, -16(%rcx)
	movq	-16(%rbp), %rcx
	movslq	(%rax), %rdx
	cmpb	$0, (%rcx,%rdx)
	je	.LBB37_8
	.p2align	4, 0x90
.LBB37_4:                               # %for.body.1
                                        #   Parent Loop BB37_2 Depth=1
                                        # =>  This Inner Loop Header: Depth=2
	movq	-24(%rbp), %rcx
	movslq	-4(%rbp), %rdx
	movzbl	(%rcx,%rdx), %ecx
	movq	-16(%rbp), %rdx
	movslq	(%rax), %rsi
	cmpb	(%rdx,%rsi), %cl
	je	.LBB37_5
# %bb.9:                                # %else
                                        #   in Loop: Header=BB37_4 Depth=2
	incl	(%rax)
	movq	-16(%rbp), %rcx
	movslq	(%rax), %rdx
	cmpb	$0, (%rcx,%rdx)
	jne	.LBB37_4
.LBB37_8:                               # %for.end.1
                                        #   in Loop: Header=BB37_2 Depth=1
	incl	-4(%rbp)
	movq	-24(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$0, (%rax,%rcx)
	jne	.LBB37_2
.LBB37_6:                               # %for.end
	movl	$-1, %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB37_5:                               # %then
	.cfi_def_cfa %rbp, 16
	movl	-4(%rbp), %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end37:
	.size	find_any__3__byte_ptr1__byte_ptr1__int__ret_int, .Lfunc_end37-find_any__3__byte_ptr1__byte_ptr1__int__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	find_substring__3__byte_ptr1__byte_ptr1__int__ret_int # -- Begin function find_substring__3__byte_ptr1__byte_ptr1__int__ret_int
	.p2align	4, 0x90
	.type	find_substring__3__byte_ptr1__byte_ptr1__int__ret_int,@function
find_substring__3__byte_ptr1__byte_ptr1__int__ret_int: # @find_substring__3__byte_ptr1__byte_ptr1__int__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	subq	$32, %rsp
	movq	%rdi, -24(%rbp)
	movq	%rsi, -16(%rbp)
	movl	%edx, -8(%rbp)
	movl	$0, -4(%rbp)
	movq	-24(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB38_3
	.p2align	4, 0x90
.LBB38_2:                               # %while.body
                                        # =>This Inner Loop Header: Depth=1
	incl	-4(%rbp)
	movq	-24(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$0, (%rax,%rcx)
	jne	.LBB38_2
.LBB38_3:                               # %while.end
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rax
	movq	%rax, %rsp
	movl	$0, -16(%rcx)
	movq	-16(%rbp), %rcx
	movslq	(%rax), %rdx
	cmpb	$0, (%rcx,%rdx)
	je	.LBB38_6
	.p2align	4, 0x90
.LBB38_5:                               # %while.body.1
                                        # =>This Inner Loop Header: Depth=1
	incl	(%rax)
	movq	-16(%rbp), %rcx
	movslq	(%rax), %rdx
	cmpb	$0, (%rcx,%rdx)
	jne	.LBB38_5
.LBB38_6:                               # %while.end.1
	cmpl	$0, (%rax)
	je	.LBB38_7
# %bb.8:                                # %else
	movq	%rsp, %rdx
	leaq	-16(%rdx), %rcx
	movq	%rcx, %rsp
	movl	-8(%rbp), %esi
	movl	%esi, -16(%rdx)
	movl	-4(%rbp), %edx
	subl	(%rax), %edx
	cmpl	%edx, (%rcx)
	jg	.LBB38_16
	.p2align	4, 0x90
.LBB38_10:                              # %for.body
                                        # =>This Loop Header: Depth=1
                                        #     Child Loop BB38_12 Depth 2
	movq	%rsp, %rsi
	leaq	-16(%rsi), %rdx
	movq	%rdx, %rsp
	movb	$1, -16(%rsi)
	movq	%rsp, %rdi
	leaq	-16(%rdi), %rsi
	movq	%rsi, %rsp
	movl	$0, -16(%rdi)
	movl	(%rsi), %edi
	cmpl	(%rax), %edi
	jge	.LBB38_14
	.p2align	4, 0x90
.LBB38_12:                              # %for.body.1
                                        #   Parent Loop BB38_10 Depth=1
                                        # =>  This Inner Loop Header: Depth=2
	movq	-24(%rbp), %rdi
	movslq	(%rsi), %r8
	movl	(%rcx), %r9d
	addl	%r8d, %r9d
	movslq	%r9d, %r9
	movzbl	(%rdi,%r9), %edi
	movq	-16(%rbp), %r9
	cmpb	(%r9,%r8), %dil
	jne	.LBB38_13
# %bb.18:                               # %else.1
                                        #   in Loop: Header=BB38_12 Depth=2
	incl	(%rsi)
	movl	(%rsi), %edi
	cmpl	(%rax), %edi
	jl	.LBB38_12
	jmp	.LBB38_14
	.p2align	4, 0x90
.LBB38_13:                              # %then.1
                                        #   in Loop: Header=BB38_10 Depth=1
	movb	$0, (%rdx)
.LBB38_14:                              # %for.end.1
                                        #   in Loop: Header=BB38_10 Depth=1
	cmpb	$0, (%rdx)
	jne	.LBB38_15
# %bb.19:                               # %else.2
                                        #   in Loop: Header=BB38_10 Depth=1
	incl	(%rcx)
	movl	-4(%rbp), %edx
	subl	(%rax), %edx
	cmpl	%edx, (%rcx)
	jle	.LBB38_10
.LBB38_16:                              # %for.end
	movl	$-1, %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB38_7:                               # %then
	.cfi_def_cfa %rbp, 16
	movl	-8(%rbp), %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB38_15:                              # %then.2
	.cfi_def_cfa %rbp, 16
	movl	(%rcx), %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end38:
	.size	find_substring__3__byte_ptr1__byte_ptr1__int__ret_int, .Lfunc_end38-find_substring__3__byte_ptr1__byte_ptr1__int__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	skip_whitespace__2__byte_ptr1__int__ret_int # -- Begin function skip_whitespace__2__byte_ptr1__int__ret_int
	.p2align	4, 0x90
	.type	skip_whitespace__2__byte_ptr1__int__ret_int,@function
skip_whitespace__2__byte_ptr1__int__ret_int: # @skip_whitespace__2__byte_ptr1__int__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbx
	.cfi_def_cfa_offset 16
	subq	$16, %rsp
	.cfi_def_cfa_offset 32
	.cfi_offset %rbx, -16
	movq	%rdi, 8(%rsp)
	movl	%esi, 4(%rsp)
	.p2align	4, 0x90
.LBB39_1:                               # %while.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	8(%rsp), %rax
	movslq	4(%rsp), %rcx
	movzbl	(%rax,%rcx), %ebx
	movl	%ebx, %edi
	callq	is_whitespace__1__char__ret_bool@PLT
	testb	%bl, %bl
	je	.LBB39_4
# %bb.2:                                # %while.cond
                                        #   in Loop: Header=BB39_1 Depth=1
	testb	$1, %al
	je	.LBB39_4
# %bb.3:                                # %while.body
                                        #   in Loop: Header=BB39_1 Depth=1
	incl	4(%rsp)
	jmp	.LBB39_1
.LBB39_4:                               # %while.end
	movl	4(%rsp), %eax
	addq	$16, %rsp
	.cfi_def_cfa_offset 16
	popq	%rbx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end39:
	.size	skip_whitespace__2__byte_ptr1__int__ret_int, .Lfunc_end39-skip_whitespace__2__byte_ptr1__int__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	trim_end__1__byte_ptr1__ret_void # -- Begin function trim_end__1__byte_ptr1__ret_void
	.p2align	4, 0x90
	.type	trim_end__1__byte_ptr1__ret_void,@function
trim_end__1__byte_ptr1__ret_void:       # @trim_end__1__byte_ptr1__ret_void
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbx
	.cfi_def_cfa_offset 16
	subq	$16, %rsp
	.cfi_def_cfa_offset 32
	.cfi_offset %rbx, -16
	movq	%rdi, 8(%rsp)
	movl	$0, 4(%rsp)
	movq	8(%rsp), %rax
	movslq	4(%rsp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB40_3
	.p2align	4, 0x90
.LBB40_2:                               # %while.body
                                        # =>This Inner Loop Header: Depth=1
	incl	4(%rsp)
	movq	8(%rsp), %rax
	movslq	4(%rsp), %rcx
	cmpb	$0, (%rax,%rcx)
	jne	.LBB40_2
	jmp	.LBB40_3
	.p2align	4, 0x90
.LBB40_4:                               # %while.cond.1
                                        #   in Loop: Header=BB40_3 Depth=1
	testb	$1, %al
	je	.LBB40_6
# %bb.5:                                # %while.body.1
                                        #   in Loop: Header=BB40_3 Depth=1
	decl	4(%rsp)
.LBB40_3:                               # %while.cond.1
                                        # =>This Inner Loop Header: Depth=1
	movl	4(%rsp), %ebx
	movq	8(%rsp), %rax
	leal	-1(%rbx), %ecx
	movslq	%ecx, %rcx
	movzbl	(%rax,%rcx), %edi
	callq	is_whitespace__1__char__ret_bool@PLT
	testl	%ebx, %ebx
	jg	.LBB40_4
.LBB40_6:                               # %while.end.1
	movq	8(%rsp), %rax
	movslq	4(%rsp), %rcx
	movb	$0, (%rax,%rcx)
	addq	$16, %rsp
	.cfi_def_cfa_offset 16
	popq	%rbx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end40:
	.size	trim_end__1__byte_ptr1__ret_void, .Lfunc_end40-trim_end__1__byte_ptr1__ret_void
	.cfi_endproc
                                        # -- End function
	.globl	compare_n__3__byte_ptr1__byte_ptr1__int__ret_int # -- Begin function compare_n__3__byte_ptr1__byte_ptr1__int__ret_int
	.p2align	4, 0x90
	.type	compare_n__3__byte_ptr1__byte_ptr1__int__ret_int,@function
compare_n__3__byte_ptr1__byte_ptr1__int__ret_int: # @compare_n__3__byte_ptr1__byte_ptr1__int__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	movq	%rdi, -24(%rsp)
	movq	%rsi, -8(%rsp)
	movl	%edx, -12(%rsp)
	movl	$0, -28(%rsp)
	movl	-28(%rsp), %eax
	cmpl	-12(%rsp), %eax
	jge	.LBB41_4
	.p2align	4, 0x90
.LBB41_1:                               # %for.body
                                        # =>This Inner Loop Header: Depth=1
	movq	-24(%rsp), %rax
	movslq	-28(%rsp), %rcx
	movzbl	(%rax,%rcx), %eax
	movq	-8(%rsp), %rdx
	cmpb	(%rdx,%rcx), %al
	jne	.LBB41_5
# %bb.2:                                # %else
                                        #   in Loop: Header=BB41_1 Depth=1
	movq	-24(%rsp), %rax
	movslq	-28(%rsp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB41_4
# %bb.3:                                # %else.1
                                        #   in Loop: Header=BB41_1 Depth=1
	incl	-28(%rsp)
	movl	-28(%rsp), %eax
	cmpl	-12(%rsp), %eax
	jl	.LBB41_1
.LBB41_4:                               # %for.end
	xorl	%eax, %eax
	retq
.LBB41_5:                               # %then
	movq	-24(%rsp), %rax
	movslq	-28(%rsp), %rcx
	movzbl	(%rax,%rcx), %eax
	movq	-8(%rsp), %rdx
	subb	(%rdx,%rcx), %al
	movsbl	%al, %eax
	retq
.Lfunc_end41:
	.size	compare_n__3__byte_ptr1__byte_ptr1__int__ret_int, .Lfunc_end41-compare_n__3__byte_ptr1__byte_ptr1__int__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	compare_ignore_case__2__byte_ptr1__byte_ptr1__ret_int # -- Begin function compare_ignore_case__2__byte_ptr1__byte_ptr1__ret_int
	.p2align	4, 0x90
	.type	compare_ignore_case__2__byte_ptr1__byte_ptr1__ret_int,@function
compare_ignore_case__2__byte_ptr1__byte_ptr1__ret_int: # @compare_ignore_case__2__byte_ptr1__byte_ptr1__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	pushq	%r15
	pushq	%r14
	pushq	%r12
	pushq	%rbx
	subq	$32, %rsp
	.cfi_offset %rbx, -48
	.cfi_offset %r12, -40
	.cfi_offset %r14, -32
	.cfi_offset %r15, -24
	movq	%rdi, -56(%rbp)
	movq	%rsi, -48(%rbp)
	movl	$0, -36(%rbp)
	movq	-56(%rbp), %rcx
	movslq	-36(%rbp), %rax
	cmpb	$0, (%rcx,%rax)
	je	.LBB42_7
	.p2align	4, 0x90
.LBB42_2:                               # %while.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	-48(%rbp), %rcx
	movzbl	(%rcx,%rax), %eax
	testl	%eax, %eax
	je	.LBB42_7
# %bb.3:                                # %while.body
                                        #   in Loop: Header=BB42_2 Depth=1
	movq	%rsp, %r15
	leaq	-16(%r15), %rbx
	movq	%rbx, %rsp
	movq	-56(%rbp), %rax
	movslq	-36(%rbp), %rcx
	movzbl	(%rax,%rcx), %edi
	callq	to_lower__1__char__ret_char@PLT
	movb	%al, -16(%r15)
	movq	%rsp, %r12
	leaq	-16(%r12), %r14
	movq	%r14, %rsp
	movq	-48(%rbp), %rax
	movslq	-36(%rbp), %rcx
	movzbl	(%rax,%rcx), %edi
	callq	to_lower__1__char__ret_char@PLT
	movb	%al, -16(%r12)
	cmpb	%al, -16(%r15)
	jne	.LBB42_4
# %bb.6:                                # %else
                                        #   in Loop: Header=BB42_2 Depth=1
	incl	-36(%rbp)
	movq	-56(%rbp), %rcx
	movslq	-36(%rbp), %rax
	cmpb	$0, (%rcx,%rax)
	jne	.LBB42_2
.LBB42_7:                               # %while.end
	movq	-56(%rbp), %rax
	movslq	-36(%rbp), %rcx
	movzbl	(%rax,%rcx), %edi
	callq	to_lower__1__char__ret_char@PLT
	movl	%eax, %ebx
	movq	-48(%rbp), %rax
	movslq	-36(%rbp), %rcx
	movzbl	(%rax,%rcx), %edi
	callq	to_lower__1__char__ret_char@PLT
	subb	%al, %bl
	movsbl	%bl, %eax
	jmp	.LBB42_5
.LBB42_4:                               # %then
	movzbl	(%rbx), %eax
	subb	(%r14), %al
	movsbl	%al, %eax
.LBB42_5:                               # %then
	leaq	-32(%rbp), %rsp
	popq	%rbx
	popq	%r12
	popq	%r14
	popq	%r15
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end42:
	.size	compare_ignore_case__2__byte_ptr1__byte_ptr1__ret_int, .Lfunc_end42-compare_ignore_case__2__byte_ptr1__byte_ptr1__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	starts_with__2__byte_ptr1__byte_ptr1__ret_bool # -- Begin function starts_with__2__byte_ptr1__byte_ptr1__ret_bool
	.p2align	4, 0x90
	.type	starts_with__2__byte_ptr1__byte_ptr1__ret_bool,@function
starts_with__2__byte_ptr1__byte_ptr1__ret_bool: # @starts_with__2__byte_ptr1__byte_ptr1__ret_bool
	.cfi_startproc
# %bb.0:                                # %entry
	movq	%rdi, -8(%rsp)
	movq	%rsi, -16(%rsp)
	movl	$0, -20(%rsp)
	movq	-16(%rsp), %rax
	movslq	-20(%rsp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB43_4
	.p2align	4, 0x90
.LBB43_2:                               # %while.body
                                        # =>This Inner Loop Header: Depth=1
	movq	-8(%rsp), %rax
	movslq	-20(%rsp), %rcx
	movzbl	(%rax,%rcx), %eax
	movq	-16(%rsp), %rdx
	cmpb	(%rdx,%rcx), %al
	jne	.LBB43_5
# %bb.3:                                # %else
                                        #   in Loop: Header=BB43_2 Depth=1
	incl	-20(%rsp)
	movq	-16(%rsp), %rax
	movslq	-20(%rsp), %rcx
	cmpb	$0, (%rax,%rcx)
	jne	.LBB43_2
.LBB43_4:                               # %while.end
	movb	$1, %al
	retq
.LBB43_5:                               # %then
	xorl	%eax, %eax
	retq
.Lfunc_end43:
	.size	starts_with__2__byte_ptr1__byte_ptr1__ret_bool, .Lfunc_end43-starts_with__2__byte_ptr1__byte_ptr1__ret_bool
	.cfi_endproc
                                        # -- End function
	.globl	ends_with__2__byte_ptr1__byte_ptr1__ret_bool # -- Begin function ends_with__2__byte_ptr1__byte_ptr1__ret_bool
	.p2align	4, 0x90
	.type	ends_with__2__byte_ptr1__byte_ptr1__ret_bool,@function
ends_with__2__byte_ptr1__byte_ptr1__ret_bool: # @ends_with__2__byte_ptr1__byte_ptr1__ret_bool
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	subq	$32, %rsp
	movq	%rdi, -24(%rbp)
	movq	%rsi, -16(%rbp)
	movl	$0, -4(%rbp)
	movq	-24(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB44_3
	.p2align	4, 0x90
.LBB44_2:                               # %while.body
                                        # =>This Inner Loop Header: Depth=1
	incl	-4(%rbp)
	movq	-24(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$0, (%rax,%rcx)
	jne	.LBB44_2
.LBB44_3:                               # %while.end
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rax
	movq	%rax, %rsp
	movl	$0, -16(%rcx)
	movq	-16(%rbp), %rcx
	movslq	(%rax), %rdx
	cmpb	$0, (%rcx,%rdx)
	je	.LBB44_6
	.p2align	4, 0x90
.LBB44_5:                               # %while.body.1
                                        # =>This Inner Loop Header: Depth=1
	incl	(%rax)
	movq	-16(%rbp), %rcx
	movslq	(%rax), %rdx
	cmpb	$0, (%rcx,%rdx)
	jne	.LBB44_5
.LBB44_6:                               # %while.end.1
	movl	(%rax), %ecx
	cmpl	-4(%rbp), %ecx
	jle	.LBB44_9
.LBB44_7:                               # %then
	xorl	%eax, %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB44_9:                               # %else
	.cfi_def_cfa %rbp, 16
	movq	%rsp, %rdx
	leaq	-16(%rdx), %rcx
	movq	%rcx, %rsp
	movl	-4(%rbp), %esi
	subl	(%rax), %esi
	movl	%esi, -16(%rdx)
	movq	%rsp, %rsi
	leaq	-16(%rsi), %rdx
	movq	%rdx, %rsp
	movl	$0, -16(%rsi)
	movl	(%rdx), %esi
	cmpl	(%rax), %esi
	jge	.LBB44_13
	.p2align	4, 0x90
.LBB44_11:                              # %for.body
                                        # =>This Inner Loop Header: Depth=1
	movq	-24(%rbp), %rsi
	movslq	(%rdx), %rdi
	movl	(%rcx), %r8d
	addl	%edi, %r8d
	movslq	%r8d, %r8
	movzbl	(%rsi,%r8), %esi
	movq	-16(%rbp), %r8
	cmpb	(%r8,%rdi), %sil
	jne	.LBB44_7
# %bb.12:                               # %else.1
                                        #   in Loop: Header=BB44_11 Depth=1
	incl	(%rdx)
	movl	(%rdx), %esi
	cmpl	(%rax), %esi
	jl	.LBB44_11
.LBB44_13:                              # %for.end
	movb	$1, %al
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end44:
	.size	ends_with__2__byte_ptr1__byte_ptr1__ret_bool, .Lfunc_end44-ends_with__2__byte_ptr1__byte_ptr1__ret_bool
	.cfi_endproc
                                        # -- End function
	.globl	copy_string__1__byte_ptr1__ret_byte # -- Begin function copy_string__1__byte_ptr1__ret_byte
	.p2align	4, 0x90
	.type	copy_string__1__byte_ptr1__ret_byte,@function
copy_string__1__byte_ptr1__ret_byte:    # @copy_string__1__byte_ptr1__ret_byte
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	pushq	%r14
	pushq	%rbx
	subq	$16, %rsp
	.cfi_offset %rbx, -32
	.cfi_offset %r14, -24
	movq	%rdi, -32(%rbp)
	movl	$0, -20(%rbp)
	movq	-32(%rbp), %rax
	movslq	-20(%rbp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB45_3
	.p2align	4, 0x90
.LBB45_2:                               # %while.body
                                        # =>This Inner Loop Header: Depth=1
	incl	-20(%rbp)
	movq	-32(%rbp), %rax
	movslq	-20(%rbp), %rcx
	cmpb	$0, (%rax,%rcx)
	jne	.LBB45_2
.LBB45_3:                               # %while.end
	movq	%rsp, %r14
	leaq	-16(%r14), %rbx
	movq	%rbx, %rsp
	movl	-20(%rbp), %edi
	incq	%rdi
	callq	malloc@PLT
	movq	%rax, -16(%r14)
	testq	%rax, %rax
	je	.LBB45_4
# %bb.6:                                # %else
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rax
	movq	%rax, %rsp
	movl	$0, -16(%rcx)
	movl	(%rax), %ecx
	cmpl	-20(%rbp), %ecx
	jg	.LBB45_9
	.p2align	4, 0x90
.LBB45_8:                               # %for.body
                                        # =>This Inner Loop Header: Depth=1
	movq	-32(%rbp), %rcx
	movslq	(%rax), %rdx
	movzbl	(%rcx,%rdx), %ecx
	movq	(%rbx), %rsi
	movb	%cl, (%rsi,%rdx)
	incl	(%rax)
	movl	(%rax), %ecx
	cmpl	-20(%rbp), %ecx
	jle	.LBB45_8
.LBB45_9:                               # %for.end
	movq	(%rbx), %rax
	jmp	.LBB45_5
.LBB45_4:                               # %then
	xorl	%eax, %eax
.LBB45_5:                               # %then
	leaq	-16(%rbp), %rsp
	popq	%rbx
	popq	%r14
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end45:
	.size	copy_string__1__byte_ptr1__ret_byte, .Lfunc_end45-copy_string__1__byte_ptr1__ret_byte
	.cfi_endproc
                                        # -- End function
	.globl	copy_n__2__byte_ptr1__int__ret_byte # -- Begin function copy_n__2__byte_ptr1__int__ret_byte
	.p2align	4, 0x90
	.type	copy_n__2__byte_ptr1__int__ret_byte,@function
copy_n__2__byte_ptr1__int__ret_byte:    # @copy_n__2__byte_ptr1__int__ret_byte
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	subq	$32, %rsp
	movq	%rdi, -24(%rbp)
	movl	%esi, -4(%rbp)
	movl	%esi, %edi
	incq	%rdi
	callq	malloc@PLT
	movq	%rax, -16(%rbp)
	testq	%rax, %rax
	je	.LBB46_1
# %bb.3:                                # %else
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rax
	movq	%rax, %rsp
	movl	$0, -16(%rcx)
	movslq	(%rax), %rcx
	cmpl	-4(%rbp), %ecx
	jge	.LBB46_7
	.p2align	4, 0x90
.LBB46_5:                               # %for.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	-24(%rbp), %rdx
	movzbl	(%rdx,%rcx), %ecx
	testl	%ecx, %ecx
	je	.LBB46_7
# %bb.6:                                # %for.body
                                        #   in Loop: Header=BB46_5 Depth=1
	movq	-24(%rbp), %rcx
	movslq	(%rax), %rdx
	movzbl	(%rcx,%rdx), %ecx
	movq	-16(%rbp), %rsi
	movb	%cl, (%rsi,%rdx)
	incl	(%rax)
	movslq	(%rax), %rcx
	cmpl	-4(%rbp), %ecx
	jl	.LBB46_5
.LBB46_7:                               # %for.end
	movq	-16(%rbp), %rax
	movslq	-4(%rbp), %rcx
	movb	$0, (%rax,%rcx)
	movq	-16(%rbp), %rax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB46_1:                               # %then
	.cfi_def_cfa %rbp, 16
	xorl	%eax, %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end46:
	.size	copy_n__2__byte_ptr1__int__ret_byte, .Lfunc_end46-copy_n__2__byte_ptr1__int__ret_byte
	.cfi_endproc
                                        # -- End function
	.globl	substring__3__byte_ptr1__int__int__ret_byte # -- Begin function substring__3__byte_ptr1__int__int__ret_byte
	.p2align	4, 0x90
	.type	substring__3__byte_ptr1__int__int__ret_byte,@function
substring__3__byte_ptr1__int__int__ret_byte: # @substring__3__byte_ptr1__int__int__ret_byte
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	subq	$32, %rsp
	movq	%rdi, -24(%rbp)
	movl	%esi, -8(%rbp)
	movl	%edx, -4(%rbp)
	movl	%edx, %edi
	incq	%rdi
	callq	malloc@PLT
	movq	%rax, -16(%rbp)
	testq	%rax, %rax
	je	.LBB47_1
# %bb.3:                                # %else
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rax
	movq	%rax, %rsp
	movl	$0, -16(%rcx)
	movl	(%rax), %ecx
	cmpl	-4(%rbp), %ecx
	jge	.LBB47_7
	.p2align	4, 0x90
.LBB47_5:                               # %for.cond
                                        # =>This Inner Loop Header: Depth=1
	addl	-8(%rbp), %ecx
	movq	-24(%rbp), %rdx
	movslq	%ecx, %rcx
	movzbl	(%rdx,%rcx), %ecx
	testl	%ecx, %ecx
	je	.LBB47_7
# %bb.6:                                # %for.body
                                        #   in Loop: Header=BB47_5 Depth=1
	movq	-24(%rbp), %rcx
	movslq	(%rax), %rdx
	movl	-8(%rbp), %esi
	addl	%edx, %esi
	movslq	%esi, %rsi
	movzbl	(%rcx,%rsi), %ecx
	movq	-16(%rbp), %rsi
	movb	%cl, (%rsi,%rdx)
	incl	(%rax)
	movl	(%rax), %ecx
	cmpl	-4(%rbp), %ecx
	jl	.LBB47_5
.LBB47_7:                               # %for.end
	movq	-16(%rbp), %rax
	movslq	-4(%rbp), %rcx
	movb	$0, (%rax,%rcx)
	movq	-16(%rbp), %rax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB47_1:                               # %then
	.cfi_def_cfa %rbp, 16
	xorl	%eax, %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end47:
	.size	substring__3__byte_ptr1__int__int__ret_byte, .Lfunc_end47-substring__3__byte_ptr1__int__int__ret_byte
	.cfi_endproc
                                        # -- End function
	.globl	concat__2__byte_ptr1__byte_ptr1__ret_byte # -- Begin function concat__2__byte_ptr1__byte_ptr1__ret_byte
	.p2align	4, 0x90
	.type	concat__2__byte_ptr1__byte_ptr1__ret_byte,@function
concat__2__byte_ptr1__byte_ptr1__ret_byte: # @concat__2__byte_ptr1__byte_ptr1__ret_byte
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	pushq	%r15
	pushq	%r14
	pushq	%rbx
	subq	$24, %rsp
	.cfi_offset %rbx, -40
	.cfi_offset %r14, -32
	.cfi_offset %r15, -24
	movq	%rdi, -48(%rbp)
	movq	%rsi, -40(%rbp)
	movl	$0, -28(%rbp)
	movq	-48(%rbp), %rax
	movslq	-28(%rbp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB48_3
	.p2align	4, 0x90
.LBB48_2:                               # %while.body
                                        # =>This Inner Loop Header: Depth=1
	incl	-28(%rbp)
	movq	-48(%rbp), %rax
	movslq	-28(%rbp), %rcx
	cmpb	$0, (%rax,%rcx)
	jne	.LBB48_2
.LBB48_3:                               # %while.end
	movq	%rsp, %rax
	leaq	-16(%rax), %rbx
	movq	%rbx, %rsp
	movl	$0, -16(%rax)
	movq	-40(%rbp), %rax
	movslq	(%rbx), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB48_6
	.p2align	4, 0x90
.LBB48_5:                               # %while.body.1
                                        # =>This Inner Loop Header: Depth=1
	incl	(%rbx)
	movq	-40(%rbp), %rax
	movslq	(%rbx), %rcx
	cmpb	$0, (%rax,%rcx)
	jne	.LBB48_5
.LBB48_6:                               # %while.end.1
	movq	%rsp, %r15
	leaq	-16(%r15), %r14
	movq	%r14, %rsp
	movl	-28(%rbp), %eax
	movl	(%rbx), %ecx
	leaq	(%rax,%rcx), %rdi
	incq	%rdi
	callq	malloc@PLT
	movq	%rax, -16(%r15)
	testq	%rax, %rax
	je	.LBB48_7
# %bb.9:                                # %else
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rax
	movq	%rax, %rsp
	movl	$0, -16(%rcx)
	movl	(%rax), %ecx
	cmpl	-28(%rbp), %ecx
	jge	.LBB48_12
	.p2align	4, 0x90
.LBB48_11:                              # %for.body
                                        # =>This Inner Loop Header: Depth=1
	movq	-48(%rbp), %rcx
	movslq	(%rax), %rdx
	movzbl	(%rcx,%rdx), %ecx
	movq	(%r14), %rsi
	movb	%cl, (%rsi,%rdx)
	incl	(%rax)
	movl	(%rax), %ecx
	cmpl	-28(%rbp), %ecx
	jl	.LBB48_11
.LBB48_12:                              # %for.end
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rax
	movq	%rax, %rsp
	movl	$0, -16(%rcx)
	movl	(%rax), %ecx
	cmpl	(%rbx), %ecx
	jge	.LBB48_15
	.p2align	4, 0x90
.LBB48_14:                              # %for.body.1
                                        # =>This Inner Loop Header: Depth=1
	movq	-40(%rbp), %rcx
	movslq	(%rax), %rdx
	movzbl	(%rcx,%rdx), %ecx
	movq	(%r14), %rsi
	movl	-28(%rbp), %edi
	addl	%edx, %edi
	movslq	%edi, %rdx
	movb	%cl, (%rsi,%rdx)
	incl	(%rax)
	movl	(%rax), %ecx
	cmpl	(%rbx), %ecx
	jl	.LBB48_14
.LBB48_15:                              # %for.end.1
	movq	(%r14), %rax
	movl	-28(%rbp), %ecx
	addl	(%rbx), %ecx
	movslq	%ecx, %rcx
	movb	$0, (%rax,%rcx)
	movq	(%r14), %rax
	jmp	.LBB48_8
.LBB48_7:                               # %then
	xorl	%eax, %eax
.LBB48_8:                               # %then
	leaq	-24(%rbp), %rsp
	popq	%rbx
	popq	%r14
	popq	%r15
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end48:
	.size	concat__2__byte_ptr1__byte_ptr1__ret_byte, .Lfunc_end48-concat__2__byte_ptr1__byte_ptr1__ret_byte
	.cfi_endproc
                                        # -- End function
	.globl	parse_int__3__byte_ptr1__int__int_ptr1__ret_int # -- Begin function parse_int__3__byte_ptr1__int__int_ptr1__ret_int
	.p2align	4, 0x90
	.type	parse_int__3__byte_ptr1__int__int_ptr1__ret_int,@function
parse_int__3__byte_ptr1__int__int_ptr1__ret_int: # @parse_int__3__byte_ptr1__int__int_ptr1__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	pushq	%rbx
	subq	$40, %rsp
	.cfi_offset %rbx, -24
	movq	%rdi, -24(%rbp)
	movl	%esi, -36(%rbp)
	movq	%rdx, -32(%rbp)
	callq	skip_whitespace__2__byte_ptr1__int__ret_int@PLT
	movl	%eax, -16(%rbp)
	movb	$0, -9(%rbp)
	movq	-24(%rbp), %rcx
	cltq
	cmpb	$45, (%rcx,%rax)
	jne	.LBB49_2
# %bb.1:                                # %then
	movb	$1, -9(%rbp)
	jmp	.LBB49_3
.LBB49_2:                               # %else
	movq	-24(%rbp), %rax
	movslq	-16(%rbp), %rcx
	cmpb	$43, (%rax,%rcx)
	jne	.LBB49_4
.LBB49_3:                               # %elif_then_0
	incl	-16(%rbp)
.LBB49_4:                               # %ifcont
	movq	%rsp, %rax
	leaq	-16(%rax), %rbx
	movq	%rbx, %rsp
	movl	$0, -16(%rax)
	.p2align	4, 0x90
.LBB49_5:                               # %while.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	-24(%rbp), %rax
	movslq	-16(%rbp), %rcx
	movzbl	(%rax,%rcx), %edi
	callq	is_digit__1__char__ret_bool@PLT
	testb	$1, %al
	je	.LBB49_7
# %bb.6:                                # %while.body
                                        #   in Loop: Header=BB49_5 Depth=1
	movl	(%rbx), %eax
	leal	(%rax,%rax,4), %eax
	movq	-24(%rbp), %rcx
	movslq	-16(%rbp), %rdx
	movzbl	(%rcx,%rdx), %ecx
	addb	$-48, %cl
	movzbl	%cl, %ecx
	leal	(%rcx,%rax,2), %eax
	movl	%eax, (%rbx)
	incl	-16(%rbp)
	jmp	.LBB49_5
.LBB49_7:                               # %while.end
	movl	-16(%rbp), %eax
	movq	-32(%rbp), %rcx
	movl	%eax, (%rcx)
	cmpb	$1, -9(%rbp)
	jne	.LBB49_9
# %bb.8:                                # %then.1
	xorl	%eax, %eax
	subl	(%rbx), %eax
	leaq	-8(%rbp), %rsp
	popq	%rbx
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB49_9:                               # %else.1
	.cfi_def_cfa %rbp, 16
	movl	(%rbx), %eax
	leaq	-8(%rbp), %rsp
	popq	%rbx
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end49:
	.size	parse_int__3__byte_ptr1__int__int_ptr1__ret_int, .Lfunc_end49-parse_int__3__byte_ptr1__int__int_ptr1__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	parse_hex__3__byte_ptr1__int__int_ptr1__ret_int # -- Begin function parse_hex__3__byte_ptr1__int__int_ptr1__ret_int
	.p2align	4, 0x90
	.type	parse_hex__3__byte_ptr1__int__int_ptr1__ret_int,@function
parse_hex__3__byte_ptr1__int__int_ptr1__ret_int: # @parse_hex__3__byte_ptr1__int__int_ptr1__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	pushq	%r14
	pushq	%rbx
	subq	$32, %rsp
	.cfi_offset %rbx, -32
	.cfi_offset %r14, -24
	movq	%rdi, -32(%rbp)
	movl	%esi, -44(%rbp)
	movq	%rdx, -40(%rbp)
	callq	skip_whitespace__2__byte_ptr1__int__ret_int@PLT
	movl	%eax, -20(%rbp)
	movq	-32(%rbp), %rcx
	movslq	%eax, %rdx
	leal	1(%rdx), %eax
	cltq
	movzbl	(%rcx,%rax), %eax
	addb	$-88, %al
	testb	$-33, %al
	sete	%al
	cmpb	$48, (%rcx,%rdx)
	jne	.LBB50_3
# %bb.1:                                # %entry
	testb	%al, %al
	je	.LBB50_3
# %bb.2:                                # %then
	addl	$2, -20(%rbp)
.LBB50_3:                               # %ifcont
	movq	%rsp, %rax
	leaq	-16(%rax), %rbx
	movq	%rbx, %rsp
	movl	$0, -16(%rax)
	.p2align	4, 0x90
.LBB50_4:                               # %while.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	-32(%rbp), %rax
	movslq	-20(%rbp), %rcx
	movzbl	(%rax,%rcx), %edi
	callq	is_hex_digit__1__char__ret_bool@PLT
	testb	$1, %al
	je	.LBB50_6
# %bb.5:                                # %while.body
                                        #   in Loop: Header=BB50_4 Depth=1
	movq	%rsp, %r14
	leaq	-16(%r14), %rsp
	movq	-32(%rbp), %rax
	movslq	-20(%rbp), %rcx
	movzbl	(%rax,%rcx), %edi
	callq	hex_to_int__1__char__ret_int@PLT
	movl	%eax, -16(%r14)
	movl	(%rbx), %ecx
	shll	$4, %ecx
	addl	%eax, %ecx
	movl	%ecx, (%rbx)
	incl	-20(%rbp)
	jmp	.LBB50_4
.LBB50_6:                               # %while.end
	movl	-20(%rbp), %eax
	movq	-40(%rbp), %rcx
	movl	%eax, (%rcx)
	movl	(%rbx), %eax
	leaq	-16(%rbp), %rsp
	popq	%rbx
	popq	%r14
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end50:
	.size	parse_hex__3__byte_ptr1__int__int_ptr1__ret_int, .Lfunc_end50-parse_hex__3__byte_ptr1__int__int_ptr1__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	count_lines__1__byte_ptr1__ret_int # -- Begin function count_lines__1__byte_ptr1__ret_int
	.p2align	4, 0x90
	.type	count_lines__1__byte_ptr1__ret_int,@function
count_lines__1__byte_ptr1__ret_int:     # @count_lines__1__byte_ptr1__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	movq	%rdi, -8(%rsp)
	movl	$0, -16(%rsp)
	movl	$0, -12(%rsp)
	jmp	.LBB51_1
	.p2align	4, 0x90
.LBB51_4:                               # %ifcont
                                        #   in Loop: Header=BB51_1 Depth=1
	incl	-12(%rsp)
.LBB51_1:                               # %for.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	-8(%rsp), %rax
	movslq	-12(%rsp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB51_5
# %bb.2:                                # %for.body
                                        #   in Loop: Header=BB51_1 Depth=1
	movq	-8(%rsp), %rax
	movslq	-12(%rsp), %rcx
	cmpb	$10, (%rax,%rcx)
	jne	.LBB51_4
# %bb.3:                                # %then
                                        #   in Loop: Header=BB51_1 Depth=1
	incl	-16(%rsp)
	jmp	.LBB51_4
.LBB51_5:                               # %for.end
	cmpl	$0, -16(%rsp)
	jg	.LBB51_7
# %bb.6:                                # %for.end
	movq	-8(%rsp), %rax
	movzbl	(%rax), %eax
	testl	%eax, %eax
	jne	.LBB51_7
# %bb.8:                                # %ifcont.1
	movl	-16(%rsp), %eax
	retq
.LBB51_7:                               # %then.1
	incl	-16(%rsp)
	movl	-16(%rsp), %eax
	retq
.Lfunc_end51:
	.size	count_lines__1__byte_ptr1__ret_int, .Lfunc_end51-count_lines__1__byte_ptr1__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	get_line__2__byte_ptr1__int__ret_byte # -- Begin function get_line__2__byte_ptr1__int__ret_byte
	.p2align	4, 0x90
	.type	get_line__2__byte_ptr1__int__ret_byte,@function
get_line__2__byte_ptr1__int__ret_byte:  # @get_line__2__byte_ptr1__int__ret_byte
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	subq	$32, %rsp
	movq	%rdi, -24(%rbp)
	movl	%esi, -16(%rbp)
	movl	$0, -12(%rbp)
	movl	$0, -8(%rbp)
	movl	$0, -4(%rbp)
	jmp	.LBB52_1
	.p2align	4, 0x90
.LBB52_9:                               # %ifcont.1
                                        #   in Loop: Header=BB52_1 Depth=1
	incl	-4(%rbp)
.LBB52_1:                               # %for.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	-24(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB52_4
# %bb.2:                                # %for.body
                                        #   in Loop: Header=BB52_1 Depth=1
	movl	-12(%rbp), %eax
	cmpl	-16(%rbp), %eax
	je	.LBB52_3
# %bb.7:                                # %else
                                        #   in Loop: Header=BB52_1 Depth=1
	movq	-24(%rbp), %rax
	movslq	-4(%rbp), %rcx
	cmpb	$10, (%rax,%rcx)
	jne	.LBB52_9
# %bb.8:                                # %then.1
                                        #   in Loop: Header=BB52_1 Depth=1
	incl	-12(%rbp)
	jmp	.LBB52_9
.LBB52_3:                               # %then
	movl	-4(%rbp), %eax
	movl	%eax, -8(%rbp)
.LBB52_4:                               # %for.end
	movl	-12(%rbp), %eax
	cmpl	-16(%rbp), %eax
	je	.LBB52_10
# %bb.5:                                # %then.2
	xorl	%eax, %eax
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB52_10:                              # %else.2
	.cfi_def_cfa %rbp, 16
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rax
	movq	%rax, %rsp
	movl	-8(%rbp), %edx
	movl	%edx, -16(%rcx)
	.p2align	4, 0x90
.LBB52_11:                              # %while.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	-24(%rbp), %rcx
	movslq	(%rax), %rdx
	movzbl	(%rcx,%rdx), %ecx
	testb	%cl, %cl
	je	.LBB52_14
# %bb.12:                               # %while.cond
                                        #   in Loop: Header=BB52_11 Depth=1
	cmpb	$10, %cl
	je	.LBB52_14
# %bb.13:                               # %while.body
                                        #   in Loop: Header=BB52_11 Depth=1
	incl	(%rax)
	jmp	.LBB52_11
.LBB52_14:                              # %while.end
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rsp
	movl	(%rax), %edx
	subl	-8(%rbp), %edx
	movl	%edx, -16(%rcx)
	movq	-24(%rbp), %rdi
	movl	-8(%rbp), %esi
	callq	substring__3__byte_ptr1__int__int__ret_byte@PLT
	movq	%rbp, %rsp
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end52:
	.size	get_line__2__byte_ptr1__int__ret_byte, .Lfunc_end52-get_line__2__byte_ptr1__int__ret_byte
	.cfi_endproc
                                        # -- End function
	.globl	count_words__1__byte_ptr1__ret_int # -- Begin function count_words__1__byte_ptr1__ret_int
	.p2align	4, 0x90
	.type	count_words__1__byte_ptr1__ret_int,@function
count_words__1__byte_ptr1__ret_int:     # @count_words__1__byte_ptr1__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	subq	$24, %rsp
	.cfi_def_cfa_offset 32
	movq	%rdi, 16(%rsp)
	movl	$0, 12(%rsp)
	movb	$0, 7(%rsp)
	movl	$0, 8(%rsp)
	jmp	.LBB53_1
	.p2align	4, 0x90
.LBB53_3:                               # %then
                                        #   in Loop: Header=BB53_1 Depth=1
	movb	$0, 7(%rsp)
	incl	8(%rsp)
.LBB53_1:                               # %for.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	16(%rsp), %rax
	movslq	8(%rsp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB53_7
# %bb.2:                                # %for.body
                                        #   in Loop: Header=BB53_1 Depth=1
	movq	16(%rsp), %rax
	movslq	8(%rsp), %rcx
	movzbl	(%rax,%rcx), %edi
	callq	is_whitespace__1__char__ret_bool@PLT
	testb	$1, %al
	jne	.LBB53_3
# %bb.4:                                # %else
                                        #   in Loop: Header=BB53_1 Depth=1
	cmpb	$1, 7(%rsp)
	je	.LBB53_5
# %bb.6:                                # %elif_then_0
                                        #   in Loop: Header=BB53_1 Depth=1
	movb	$1, 7(%rsp)
	incl	12(%rsp)
	incl	8(%rsp)
	jmp	.LBB53_1
	.p2align	4, 0x90
.LBB53_5:                               # %ifcont
                                        #   in Loop: Header=BB53_1 Depth=1
	incl	8(%rsp)
	jmp	.LBB53_1
.LBB53_7:                               # %for.end
	movl	12(%rsp), %eax
	addq	$24, %rsp
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end53:
	.size	count_words__1__byte_ptr1__ret_int, .Lfunc_end53-count_words__1__byte_ptr1__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	replace_first__3__byte_ptr1__byte_ptr1__byte_ptr1__ret_byte # -- Begin function replace_first__3__byte_ptr1__byte_ptr1__byte_ptr1__ret_byte
	.p2align	4, 0x90
	.type	replace_first__3__byte_ptr1__byte_ptr1__byte_ptr1__ret_byte,@function
replace_first__3__byte_ptr1__byte_ptr1__byte_ptr1__ret_byte: # @replace_first__3__byte_ptr1__byte_ptr1__byte_ptr1__ret_byte
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	pushq	%r15
	pushq	%r14
	pushq	%r13
	pushq	%r12
	pushq	%rbx
	subq	$40, %rsp
	.cfi_offset %rbx, -56
	.cfi_offset %r12, -48
	.cfi_offset %r13, -40
	.cfi_offset %r14, -32
	.cfi_offset %r15, -24
	movq	%rdi, -56(%rbp)
	movq	%rsi, -72(%rbp)
	movq	%rdx, -64(%rbp)
	xorl	%edx, %edx
	callq	find_substring__3__byte_ptr1__byte_ptr1__int__ret_int@PLT
	movl	%eax, -44(%rbp)
	cmpl	$-1, %eax
	jne	.LBB54_2
# %bb.1:                                # %then
	movq	-56(%rbp), %rdi
	callq	copy_string__1__byte_ptr1__ret_byte@PLT
	jmp	.LBB54_13
.LBB54_2:                               # %else
	movq	%rsp, %rax
	leaq	-16(%rax), %rbx
	movq	%rbx, %rsp
	movl	$0, -16(%rax)
	movq	-56(%rbp), %rax
	movslq	(%rbx), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB54_5
	.p2align	4, 0x90
.LBB54_4:                               # %while.body
                                        # =>This Inner Loop Header: Depth=1
	incl	(%rbx)
	movq	-56(%rbp), %rax
	movslq	(%rbx), %rcx
	cmpb	$0, (%rax,%rcx)
	jne	.LBB54_4
.LBB54_5:                               # %while.end
	movq	%rsp, %rax
	leaq	-16(%rax), %r14
	movq	%r14, %rsp
	movl	$0, -16(%rax)
	movq	-72(%rbp), %rax
	movslq	(%r14), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB54_8
	.p2align	4, 0x90
.LBB54_7:                               # %while.body.1
                                        # =>This Inner Loop Header: Depth=1
	incl	(%r14)
	movq	-72(%rbp), %rax
	movslq	(%r14), %rcx
	cmpb	$0, (%rax,%rcx)
	jne	.LBB54_7
.LBB54_8:                               # %while.end.1
	movq	%rsp, %rax
	leaq	-16(%rax), %r15
	movq	%r15, %rsp
	movl	$0, -16(%rax)
	movq	-64(%rbp), %rax
	movslq	(%r15), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB54_11
	.p2align	4, 0x90
.LBB54_10:                              # %while.body.2
                                        # =>This Inner Loop Header: Depth=1
	incl	(%r15)
	movq	-64(%rbp), %rax
	movslq	(%r15), %rcx
	cmpb	$0, (%rax,%rcx)
	jne	.LBB54_10
.LBB54_11:                              # %while.end.2
	movq	%rsp, %rax
	leaq	-16(%rax), %rsp
	movl	(%rbx), %ecx
	subl	(%r14), %ecx
	addl	(%r15), %ecx
	movl	%ecx, -16(%rax)
	movq	%rsp, %r13
	leaq	-16(%r13), %r12
	movq	%r12, %rsp
	movl	-16(%rax), %edi
	incq	%rdi
	callq	malloc@PLT
	movq	%rax, -16(%r13)
	testq	%rax, %rax
	je	.LBB54_12
# %bb.14:                               # %else.1
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rax
	movq	%rax, %rsp
	movl	$0, -16(%rcx)
	movl	(%rax), %ecx
	cmpl	-44(%rbp), %ecx
	jge	.LBB54_17
	.p2align	4, 0x90
.LBB54_16:                              # %for.body
                                        # =>This Inner Loop Header: Depth=1
	movq	-56(%rbp), %rcx
	movslq	(%rax), %rdx
	movzbl	(%rcx,%rdx), %ecx
	movq	(%r12), %rsi
	movb	%cl, (%rsi,%rdx)
	incl	(%rax)
	movl	(%rax), %ecx
	cmpl	-44(%rbp), %ecx
	jl	.LBB54_16
.LBB54_17:                              # %for.end
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rax
	movq	%rax, %rsp
	movl	$0, -16(%rcx)
	movl	(%rax), %ecx
	cmpl	(%r15), %ecx
	jge	.LBB54_20
	.p2align	4, 0x90
.LBB54_19:                              # %for.body.1
                                        # =>This Inner Loop Header: Depth=1
	movq	-64(%rbp), %rcx
	movslq	(%rax), %rdx
	movzbl	(%rcx,%rdx), %ecx
	movq	(%r12), %rsi
	movl	-44(%rbp), %edi
	addl	%edx, %edi
	movslq	%edi, %rdx
	movb	%cl, (%rsi,%rdx)
	incl	(%rax)
	movl	(%rax), %ecx
	cmpl	(%r15), %ecx
	jl	.LBB54_19
.LBB54_20:                              # %for.end.1
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rax
	movq	%rax, %rsp
	movl	-44(%rbp), %edx
	addl	(%r14), %edx
	movl	%edx, -16(%rcx)
	movl	(%rax), %ecx
	cmpl	(%rbx), %ecx
	jg	.LBB54_23
	.p2align	4, 0x90
.LBB54_22:                              # %for.body.2
                                        # =>This Inner Loop Header: Depth=1
	movq	-56(%rbp), %rcx
	movslq	(%rax), %rdx
	movzbl	(%rcx,%rdx), %ecx
	movq	(%r12), %rsi
	movl	(%r14), %edi
	subl	%edi, %edx
	addl	(%r15), %edx
	movslq	%edx, %rdx
	movb	%cl, (%rsi,%rdx)
	incl	(%rax)
	movl	(%rax), %ecx
	cmpl	(%rbx), %ecx
	jle	.LBB54_22
.LBB54_23:                              # %for.end.2
	movq	(%r12), %rax
	jmp	.LBB54_13
.LBB54_12:                              # %then.1
	xorl	%eax, %eax
.LBB54_13:                              # %then.1
	leaq	-40(%rbp), %rsp
	popq	%rbx
	popq	%r12
	popq	%r13
	popq	%r14
	popq	%r15
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end54:
	.size	replace_first__3__byte_ptr1__byte_ptr1__byte_ptr1__ret_byte, .Lfunc_end54-replace_first__3__byte_ptr1__byte_ptr1__byte_ptr1__ret_byte
	.cfi_endproc
                                        # -- End function
	.globl	skip_until__3__byte_ptr1__int__char__ret_int # -- Begin function skip_until__3__byte_ptr1__int__char__ret_int
	.p2align	4, 0x90
	.type	skip_until__3__byte_ptr1__int__char__ret_int,@function
skip_until__3__byte_ptr1__int__char__ret_int: # @skip_until__3__byte_ptr1__int__char__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	movq	%rdi, -8(%rsp)
	movl	%esi, -12(%rsp)
	movb	%dl, -13(%rsp)
	.p2align	4, 0x90
.LBB55_1:                               # %while.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	-8(%rsp), %rax
	movslq	-12(%rsp), %rcx
	movzbl	(%rax,%rcx), %eax
	testb	%al, %al
	je	.LBB55_4
# %bb.2:                                # %while.cond
                                        #   in Loop: Header=BB55_1 Depth=1
	cmpb	-13(%rsp), %al
	je	.LBB55_4
# %bb.3:                                # %while.body
                                        #   in Loop: Header=BB55_1 Depth=1
	incl	-12(%rsp)
	jmp	.LBB55_1
.LBB55_4:                               # %while.end
	movl	-12(%rsp), %eax
	retq
.Lfunc_end55:
	.size	skip_until__3__byte_ptr1__int__char__ret_int, .Lfunc_end55-skip_until__3__byte_ptr1__int__char__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	skip_while_digit__2__byte_ptr1__int__ret_int # -- Begin function skip_while_digit__2__byte_ptr1__int__ret_int
	.p2align	4, 0x90
	.type	skip_while_digit__2__byte_ptr1__int__ret_int,@function
skip_while_digit__2__byte_ptr1__int__ret_int: # @skip_while_digit__2__byte_ptr1__int__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbx
	.cfi_def_cfa_offset 16
	subq	$16, %rsp
	.cfi_def_cfa_offset 32
	.cfi_offset %rbx, -16
	movq	%rdi, 8(%rsp)
	movl	%esi, 4(%rsp)
	.p2align	4, 0x90
.LBB56_1:                               # %while.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	8(%rsp), %rax
	movslq	4(%rsp), %rcx
	movzbl	(%rax,%rcx), %ebx
	movl	%ebx, %edi
	callq	is_digit__1__char__ret_bool@PLT
	testb	%bl, %bl
	je	.LBB56_4
# %bb.2:                                # %while.cond
                                        #   in Loop: Header=BB56_1 Depth=1
	testb	$1, %al
	je	.LBB56_4
# %bb.3:                                # %while.body
                                        #   in Loop: Header=BB56_1 Depth=1
	incl	4(%rsp)
	jmp	.LBB56_1
.LBB56_4:                               # %while.end
	movl	4(%rsp), %eax
	addq	$16, %rsp
	.cfi_def_cfa_offset 16
	popq	%rbx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end56:
	.size	skip_while_digit__2__byte_ptr1__int__ret_int, .Lfunc_end56-skip_while_digit__2__byte_ptr1__int__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	skip_while_alnum__2__byte_ptr1__int__ret_int # -- Begin function skip_while_alnum__2__byte_ptr1__int__ret_int
	.p2align	4, 0x90
	.type	skip_while_alnum__2__byte_ptr1__int__ret_int,@function
skip_while_alnum__2__byte_ptr1__int__ret_int: # @skip_while_alnum__2__byte_ptr1__int__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbx
	.cfi_def_cfa_offset 16
	subq	$16, %rsp
	.cfi_def_cfa_offset 32
	.cfi_offset %rbx, -16
	movq	%rdi, 8(%rsp)
	movl	%esi, 4(%rsp)
	.p2align	4, 0x90
.LBB57_1:                               # %while.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	8(%rsp), %rax
	movslq	4(%rsp), %rcx
	movzbl	(%rax,%rcx), %ebx
	movl	%ebx, %edi
	callq	is_alnum__1__char__ret_bool@PLT
	testb	%bl, %bl
	je	.LBB57_4
# %bb.2:                                # %while.cond
                                        #   in Loop: Header=BB57_1 Depth=1
	testb	$1, %al
	je	.LBB57_4
# %bb.3:                                # %while.body
                                        #   in Loop: Header=BB57_1 Depth=1
	incl	4(%rsp)
	jmp	.LBB57_1
.LBB57_4:                               # %while.end
	movl	4(%rsp), %eax
	addq	$16, %rsp
	.cfi_def_cfa_offset 16
	popq	%rbx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end57:
	.size	skip_while_alnum__2__byte_ptr1__int__ret_int, .Lfunc_end57-skip_while_alnum__2__byte_ptr1__int__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	skip_while_identifier__2__byte_ptr1__int__ret_int # -- Begin function skip_while_identifier__2__byte_ptr1__int__ret_int
	.p2align	4, 0x90
	.type	skip_while_identifier__2__byte_ptr1__int__ret_int,@function
skip_while_identifier__2__byte_ptr1__int__ret_int: # @skip_while_identifier__2__byte_ptr1__int__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbx
	.cfi_def_cfa_offset 16
	subq	$16, %rsp
	.cfi_def_cfa_offset 32
	.cfi_offset %rbx, -16
	movq	%rdi, 8(%rsp)
	movl	%esi, 4(%rsp)
	.p2align	4, 0x90
.LBB58_1:                               # %while.cond
                                        # =>This Inner Loop Header: Depth=1
	movq	8(%rsp), %rax
	movslq	4(%rsp), %rcx
	movzbl	(%rax,%rcx), %ebx
	movl	%ebx, %edi
	callq	is_identifier_char__1__char__ret_bool@PLT
	testb	%bl, %bl
	je	.LBB58_4
# %bb.2:                                # %while.cond
                                        #   in Loop: Header=BB58_1 Depth=1
	testb	$1, %al
	je	.LBB58_4
# %bb.3:                                # %while.body
                                        #   in Loop: Header=BB58_1 Depth=1
	incl	4(%rsp)
	jmp	.LBB58_1
.LBB58_4:                               # %while.end
	movl	4(%rsp), %eax
	addq	$16, %rsp
	.cfi_def_cfa_offset 16
	popq	%rbx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end58:
	.size	skip_while_identifier__2__byte_ptr1__int__ret_int, .Lfunc_end58-skip_while_identifier__2__byte_ptr1__int__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	match_at__3__byte_ptr1__int__byte_ptr1__ret_bool # -- Begin function match_at__3__byte_ptr1__int__byte_ptr1__ret_bool
	.p2align	4, 0x90
	.type	match_at__3__byte_ptr1__int__byte_ptr1__ret_bool,@function
match_at__3__byte_ptr1__int__byte_ptr1__ret_bool: # @match_at__3__byte_ptr1__int__byte_ptr1__ret_bool
	.cfi_startproc
# %bb.0:                                # %entry
	movq	%rdi, -8(%rsp)
	movl	%esi, -20(%rsp)
	movq	%rdx, -16(%rsp)
	movl	$0, -24(%rsp)
	movq	-16(%rsp), %rax
	movslq	-24(%rsp), %rcx
	cmpb	$0, (%rax,%rcx)
	je	.LBB59_4
	.p2align	4, 0x90
.LBB59_2:                               # %while.body
                                        # =>This Inner Loop Header: Depth=1
	movq	-8(%rsp), %rax
	movslq	-24(%rsp), %rcx
	movl	-20(%rsp), %edx
	addl	%ecx, %edx
	movslq	%edx, %rdx
	movzbl	(%rax,%rdx), %eax
	movq	-16(%rsp), %rdx
	cmpb	(%rdx,%rcx), %al
	jne	.LBB59_5
# %bb.3:                                # %else
                                        #   in Loop: Header=BB59_2 Depth=1
	incl	-24(%rsp)
	movq	-16(%rsp), %rax
	movslq	-24(%rsp), %rcx
	cmpb	$0, (%rax,%rcx)
	jne	.LBB59_2
.LBB59_4:                               # %while.end
	movb	$1, %al
	retq
.LBB59_5:                               # %then
	xorl	%eax, %eax
	retq
.Lfunc_end59:
	.size	match_at__3__byte_ptr1__int__byte_ptr1__ret_bool, .Lfunc_end59-match_at__3__byte_ptr1__int__byte_ptr1__ret_bool
	.cfi_endproc
                                        # -- End function
	.globl	string.__init                   # -- Begin function string.__init
	.p2align	4, 0x90
	.type	string.__init,@function
string.__init:                          # @string.__init
	.cfi_startproc
# %bb.0:                                # %entry
	movq	%rdi, %rax
	movq	%rsi, -8(%rsp)
	movq	%rsi, (%rdi)
	retq
.Lfunc_end60:
	.size	string.__init, .Lfunc_end60-string.__init
	.cfi_endproc
                                        # -- End function
	.globl	string.__exit                   # -- Begin function string.__exit
	.p2align	4, 0x90
	.type	string.__exit,@function
string.__exit:                          # @string.__exit
	.cfi_startproc
# %bb.0:                                # %entry
	retq
.Lfunc_end61:
	.size	string.__exit, .Lfunc_end61-string.__exit
	.cfi_endproc
                                        # -- End function
	.globl	string.val                      # -- Begin function string.val
	.p2align	4, 0x90
	.type	string.val,@function
string.val:                             # @string.val
	.cfi_startproc
# %bb.0:                                # %entry
	movq	(%rdi), %rax
	retq
.Lfunc_end62:
	.size	string.val, .Lfunc_end62-string.val
	.cfi_endproc
                                        # -- End function
	.globl	string.len                      # -- Begin function string.len
	.p2align	4, 0x90
	.type	string.len,@function
string.len:                             # @string.len
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rax
	.cfi_def_cfa_offset 16
	movq	(%rdi), %rdi
	callq	strlen@PLT
                                        # kill: def $eax killed $eax killed $rax
	popq	%rcx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end63:
	.size	string.len, .Lfunc_end63-string.len
	.cfi_endproc
                                        # -- End function
	.globl	string.set                      # -- Begin function string.set
	.p2align	4, 0x90
	.type	string.set,@function
string.set:                             # @string.set
	.cfi_startproc
# %bb.0:                                # %entry
	movq	%rsi, -16(%rsp)
	movb	$0, -17(%rsp)
	movq	%rsi, (%rdi)
	movb	$1, %al
	retq
.Lfunc_end64:
	.size	string.set, .Lfunc_end64-string.set
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__file__read_file__3__byte_ptr1__byte_arr__int__ret_int # -- Begin function standard__io__file__read_file__3__byte_ptr1__byte_arr__int__ret_int
	.p2align	4, 0x90
	.type	standard__io__file__read_file__3__byte_ptr1__byte_arr__int__ret_int,@function
standard__io__file__read_file__3__byte_ptr1__byte_arr__int__ret_int: # @standard__io__file__read_file__3__byte_ptr1__byte_arr__int__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	pushq	%rbx
	subq	$40, %rsp
	.cfi_offset %rbx, -24
	movq	%rdi, -48(%rbp)
	movq	%rsi, -40(%rbp)
	movl	%edx, -28(%rbp)
	movw	$25202, -11(%rbp)               # imm = 0x6272
	movb	$0, -9(%rbp)
	leaq	-11(%rbp), %rsi
	callq	fopen@PLT
	movq	%rax, -24(%rbp)
	testq	%rax, %rax
	je	.LBB65_1
# %bb.3:                                # %else
	movq	-24(%rbp), %rdi
	xorl	%esi, %esi
	movl	$2, %edx
	callq	fseek@PLT
	movq	%rsp, %rbx
	leaq	-16(%rbx), %rsp
	movq	-24(%rbp), %rdi
	callq	ftell@PLT
	movl	%eax, -16(%rbx)
	movq	-24(%rbp), %rdi
	callq	rewind@PLT
	movq	%rsp, %rcx
	leaq	-16(%rcx), %rax
	movq	%rax, %rsp
	movl	-16(%rbx), %edx
	movl	%edx, -16(%rcx)
	cmpl	-28(%rbp), %edx
	jle	.LBB65_5
# %bb.4:                                # %then.1
	movl	-28(%rbp), %ecx
	movl	%ecx, (%rax)
.LBB65_5:                               # %ifcont.1
	movq	%rsp, %rbx
	leaq	-16(%rbx), %rsp
	movq	-40(%rbp), %rdi
	movl	(%rax), %edx
	movq	-24(%rbp), %rcx
	movl	$1, %esi
	callq	fread@PLT
	movl	%eax, -16(%rbx)
	movq	-24(%rbp), %rdi
	callq	fclose@PLT
	movl	-16(%rbx), %eax
	leaq	-8(%rbp), %rsp
	popq	%rbx
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB65_1:                               # %then
	.cfi_def_cfa %rbp, 16
	movl	$-1, %eax
	leaq	-8(%rbp), %rsp
	popq	%rbx
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end65:
	.size	standard__io__file__read_file__3__byte_ptr1__byte_arr__int__ret_int, .Lfunc_end65-standard__io__file__read_file__3__byte_ptr1__byte_arr__int__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__file__write_file__3__byte_ptr1__byte_arr__int__ret_int # -- Begin function standard__io__file__write_file__3__byte_ptr1__byte_arr__int__ret_int
	.p2align	4, 0x90
	.type	standard__io__file__write_file__3__byte_ptr1__byte_arr__int__ret_int,@function
standard__io__file__write_file__3__byte_ptr1__byte_arr__int__ret_int: # @standard__io__file__write_file__3__byte_ptr1__byte_arr__int__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	pushq	%rbx
	subq	$40, %rsp
	.cfi_offset %rbx, -24
	movq	%rdi, -40(%rbp)
	movq	%rsi, -32(%rbp)
	movl	%edx, -16(%rbp)
	movw	$25207, -11(%rbp)               # imm = 0x6277
	movb	$0, -9(%rbp)
	leaq	-11(%rbp), %rsi
	callq	fopen@PLT
	movq	%rax, -24(%rbp)
	testq	%rax, %rax
	je	.LBB66_1
# %bb.3:                                # %else
	movq	%rsp, %rbx
	leaq	-16(%rbx), %rsp
	movq	-32(%rbp), %rdi
	movl	-16(%rbp), %edx
	movq	-24(%rbp), %rcx
	movl	$1, %esi
	callq	fwrite@PLT
	movl	%eax, -16(%rbx)
	movq	-24(%rbp), %rdi
	callq	fclose@PLT
	movl	-16(%rbx), %eax
	leaq	-8(%rbp), %rsp
	popq	%rbx
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB66_1:                               # %then
	.cfi_def_cfa %rbp, 16
	movl	$-1, %eax
	leaq	-8(%rbp), %rsp
	popq	%rbx
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end66:
	.size	standard__io__file__write_file__3__byte_ptr1__byte_arr__int__ret_int, .Lfunc_end66-standard__io__file__write_file__3__byte_ptr1__byte_arr__int__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__file__append_file__3__byte_ptr1__byte_arr__int__ret_int # -- Begin function standard__io__file__append_file__3__byte_ptr1__byte_arr__int__ret_int
	.p2align	4, 0x90
	.type	standard__io__file__append_file__3__byte_ptr1__byte_arr__int__ret_int,@function
standard__io__file__append_file__3__byte_ptr1__byte_arr__int__ret_int: # @standard__io__file__append_file__3__byte_ptr1__byte_arr__int__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	pushq	%rbx
	subq	$40, %rsp
	.cfi_offset %rbx, -24
	movq	%rdi, -40(%rbp)
	movq	%rsi, -32(%rbp)
	movl	%edx, -16(%rbp)
	movw	$25185, -11(%rbp)               # imm = 0x6261
	movb	$0, -9(%rbp)
	leaq	-11(%rbp), %rsi
	callq	fopen@PLT
	movq	%rax, -24(%rbp)
	testq	%rax, %rax
	je	.LBB67_1
# %bb.3:                                # %else
	movq	%rsp, %rbx
	leaq	-16(%rbx), %rsp
	movq	-32(%rbp), %rdi
	movl	-16(%rbp), %edx
	movq	-24(%rbp), %rcx
	movl	$1, %esi
	callq	fwrite@PLT
	movl	%eax, -16(%rbx)
	movq	-24(%rbp), %rdi
	callq	fclose@PLT
	movl	-16(%rbx), %eax
	leaq	-8(%rbp), %rsp
	popq	%rbx
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB67_1:                               # %then
	.cfi_def_cfa %rbp, 16
	movl	$-1, %eax
	leaq	-8(%rbp), %rsp
	popq	%rbx
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end67:
	.size	standard__io__file__append_file__3__byte_ptr1__byte_arr__int__ret_int, .Lfunc_end67-standard__io__file__append_file__3__byte_ptr1__byte_arr__int__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__file__get_file_size__1__byte_ptr1__ret_int # -- Begin function standard__io__file__get_file_size__1__byte_ptr1__ret_int
	.p2align	4, 0x90
	.type	standard__io__file__get_file_size__1__byte_ptr1__ret_int,@function
standard__io__file__get_file_size__1__byte_ptr1__ret_int: # @standard__io__file__get_file_size__1__byte_ptr1__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	pushq	%rbx
	subq	$24, %rsp
	.cfi_offset %rbx, -24
	movq	%rdi, -32(%rbp)
	movw	$25202, -11(%rbp)               # imm = 0x6272
	movb	$0, -9(%rbp)
	leaq	-11(%rbp), %rsi
	callq	fopen@PLT
	movq	%rax, -24(%rbp)
	testq	%rax, %rax
	je	.LBB68_1
# %bb.3:                                # %else
	movq	-24(%rbp), %rdi
	xorl	%esi, %esi
	movl	$2, %edx
	callq	fseek@PLT
	movq	%rsp, %rbx
	leaq	-16(%rbx), %rsp
	movq	-24(%rbp), %rdi
	callq	ftell@PLT
	movl	%eax, -16(%rbx)
	movq	-24(%rbp), %rdi
	callq	fclose@PLT
	movl	-16(%rbx), %eax
	leaq	-8(%rbp), %rsp
	popq	%rbx
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.LBB68_1:                               # %then
	.cfi_def_cfa %rbp, 16
	movl	$-1, %eax
	leaq	-8(%rbp), %rsp
	popq	%rbx
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
.Lfunc_end68:
	.size	standard__io__file__get_file_size__1__byte_ptr1__ret_int, .Lfunc_end68-standard__io__file__get_file_size__1__byte_ptr1__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__file__file_exists__1__byte_ptr1__ret_bool # -- Begin function standard__io__file__file_exists__1__byte_ptr1__ret_bool
	.p2align	4, 0x90
	.type	standard__io__file__file_exists__1__byte_ptr1__ret_bool,@function
standard__io__file__file_exists__1__byte_ptr1__ret_bool: # @standard__io__file__file_exists__1__byte_ptr1__ret_bool
	.cfi_startproc
# %bb.0:                                # %entry
	subq	$24, %rsp
	.cfi_def_cfa_offset 32
	movq	%rdi, 16(%rsp)
	movw	$25202, 5(%rsp)                 # imm = 0x6272
	movb	$0, 7(%rsp)
	leaq	5(%rsp), %rsi
	callq	fopen@PLT
	movq	%rax, 8(%rsp)
	testq	%rax, %rax
	je	.LBB69_1
# %bb.2:                                # %else
	movq	8(%rsp), %rdi
	callq	fclose@PLT
	movb	$1, %al
	addq	$24, %rsp
	.cfi_def_cfa_offset 8
	retq
.LBB69_1:                               # %then
	.cfi_def_cfa_offset 32
	xorl	%eax, %eax
	addq	$24, %rsp
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end69:
	.size	standard__io__file__file_exists__1__byte_ptr1__ret_bool, .Lfunc_end69-standard__io__file__file_exists__1__byte_ptr1__ret_bool
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__console__input__2__byte_arr__int__ret_int # -- Begin function standard__io__console__input__2__byte_arr__int__ret_int
	.p2align	4, 0x90
	.type	standard__io__console__input__2__byte_arr__int__ret_int,@function
standard__io__console__input__2__byte_arr__int__ret_int: # @standard__io__console__input__2__byte_arr__int__ret_int
	.cfi_startproc
# %bb.0:                                # %entry
	subq	$24, %rsp
	.cfi_def_cfa_offset 32
	movq	%rdi, 16(%rsp)
	movl	%esi, 12(%rsp)
	callq	standard__io__console__nix_input__2__byte_arr__int__ret_int@PLT
	addq	$24, %rsp
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end70:
	.size	standard__io__console__input__2__byte_arr__int__ret_int, .Lfunc_end70-standard__io__console__input__2__byte_arr__int__ret_int
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__console__nix_print__2__byte_ptr1__int__ret_void # -- Begin function standard__io__console__nix_print__2__byte_ptr1__int__ret_void
	.p2align	4, 0x90
	.type	standard__io__console__nix_print__2__byte_ptr1__int__ret_void,@function
standard__io__console__nix_print__2__byte_ptr1__int__ret_void: # @standard__io__console__nix_print__2__byte_ptr1__int__ret_void
	.cfi_startproc
# %bb.0:                                # %entry
	movq	%rdi, %r8
	movq	%rdi, -8(%rsp)
	movl	%esi, -20(%rsp)
	movslq	%esi, %r9
	movq	%r9, -16(%rsp)
	#APP
	movq	$1, %rax
	movq	$1, %rdi
	movq	%r8, %rsi
	movq	%r9, %rdx
	syscall
	#NO_APP
	retq
.Lfunc_end71:
	.size	standard__io__console__nix_print__2__byte_ptr1__int__ret_void, .Lfunc_end71-standard__io__console__nix_print__2__byte_ptr1__int__ret_void
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__console__print__2__noopstr__int__ret_void # -- Begin function standard__io__console__print__2__noopstr__int__ret_void
	.p2align	4, 0x90
	.type	standard__io__console__print__2__noopstr__int__ret_void,@function
standard__io__console__print__2__noopstr__int__ret_void: # @standard__io__console__print__2__noopstr__int__ret_void
	.cfi_startproc
# %bb.0:                                # %entry
	subq	$24, %rsp
	.cfi_def_cfa_offset 32
	movq	%rdi, 8(%rsp)
	movl	%esi, 20(%rsp)
	callq	standard__io__console__nix_print__2__byte_ptr1__int__ret_void@PLT
	leaq	8(%rsp), %rcx
	#APP

	movq	$11, %rax
	syscall

	#NO_APP
	addq	$24, %rsp
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end72:
	.size	standard__io__console__print__2__noopstr__int__ret_void, .Lfunc_end72-standard__io__console__print__2__noopstr__int__ret_void
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__console__print__1__noopstr__ret_void # -- Begin function standard__io__console__print__1__noopstr__ret_void
	.p2align	4, 0x90
	.type	standard__io__console__print__1__noopstr__ret_void,@function
standard__io__console__print__1__noopstr__ret_void: # @standard__io__console__print__1__noopstr__ret_void
	.cfi_startproc
# %bb.0:                                # %entry
	subq	$24, %rsp
	.cfi_def_cfa_offset 32
	movq	%rdi, 8(%rsp)
	callq	strlen@PLT
	movl	%eax, 20(%rsp)
	movq	8(%rsp), %rdi
	movl	%eax, %esi
	callq	standard__io__console__nix_print__2__byte_ptr1__int__ret_void@PLT
	leaq	8(%rsp), %rcx
	#APP

	movq	$11, %rax
	syscall

	#NO_APP
	addq	$24, %rsp
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end73:
	.size	standard__io__console__print__1__noopstr__ret_void, .Lfunc_end73-standard__io__console__print__1__noopstr__ret_void
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__console__print__1__byte__ret_void # -- Begin function standard__io__console__print__1__byte__ret_void
	.p2align	4, 0x90
	.type	standard__io__console__print__1__byte__ret_void,@function
standard__io__console__print__1__byte__ret_void: # @standard__io__console__print__1__byte__ret_void
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rax
	.cfi_def_cfa_offset 16
	movb	%dil, 7(%rsp)
	movb	%dil, 5(%rsp)
	movb	$0, 6(%rsp)
	leaq	5(%rsp), %rdi
	callq	standard__io__console__print__1__noopstr__ret_void@PLT
	popq	%rax
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end74:
	.size	standard__io__console__print__1__byte__ret_void, .Lfunc_end74-standard__io__console__print__1__byte__ret_void
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__console__print__1__int__ret_void # -- Begin function standard__io__console__print__1__int__ret_void
	.p2align	4, 0x90
	.type	standard__io__console__print__1__int__ret_void,@function
standard__io__console__print__1__int__ret_void: # @standard__io__console__print__1__int__ret_void
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbx
	.cfi_def_cfa_offset 16
	subq	$32, %rsp
	.cfi_def_cfa_offset 48
	.cfi_offset %rbx, -16
	movl	%edi, 4(%rsp)
	leaq	11(%rsp), %rbx
	movq	%rbx, %rsi
	callq	i32str__2__i32__byte_ptr1__ret_i32@PLT
	movq	%rbx, %rdi
	callq	standard__io__console__print__1__noopstr__ret_void@PLT
	addq	$32, %rsp
	.cfi_def_cfa_offset 16
	popq	%rbx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end75:
	.size	standard__io__console__print__1__int__ret_void, .Lfunc_end75-standard__io__console__print__1__int__ret_void
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__console__print__1__i64__ret_void # -- Begin function standard__io__console__print__1__i64__ret_void
	.p2align	4, 0x90
	.type	standard__io__console__print__1__i64__ret_void,@function
standard__io__console__print__1__i64__ret_void: # @standard__io__console__print__1__i64__ret_void
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbx
	.cfi_def_cfa_offset 16
	subq	$32, %rsp
	.cfi_def_cfa_offset 48
	.cfi_offset %rbx, -16
	movq	%rdi, (%rsp)
	leaq	11(%rsp), %rbx
	movq	%rbx, %rsi
	callq	i64str__2__i64__byte_ptr1__ret_i64@PLT
	movq	%rbx, %rdi
	callq	standard__io__console__print__1__noopstr__ret_void@PLT
	addq	$32, %rsp
	.cfi_def_cfa_offset 16
	popq	%rbx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end76:
	.size	standard__io__console__print__1__i64__ret_void, .Lfunc_end76-standard__io__console__print__1__i64__ret_void
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__console__print__1__uint__ret_void # -- Begin function standard__io__console__print__1__uint__ret_void
	.p2align	4, 0x90
	.type	standard__io__console__print__1__uint__ret_void,@function
standard__io__console__print__1__uint__ret_void: # @standard__io__console__print__1__uint__ret_void
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbx
	.cfi_def_cfa_offset 16
	subq	$32, %rsp
	.cfi_def_cfa_offset 48
	.cfi_offset %rbx, -16
	movl	%edi, 4(%rsp)
	leaq	11(%rsp), %rbx
	movq	%rbx, %rsi
	callq	u32str__2__u32__byte_ptr1__ret_u32@PLT
	movq	%rbx, %rdi
	callq	standard__io__console__print__1__noopstr__ret_void@PLT
	addq	$32, %rsp
	.cfi_def_cfa_offset 16
	popq	%rbx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end77:
	.size	standard__io__console__print__1__uint__ret_void, .Lfunc_end77-standard__io__console__print__1__uint__ret_void
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__console__print__1__u64__ret_void # -- Begin function standard__io__console__print__1__u64__ret_void
	.p2align	4, 0x90
	.type	standard__io__console__print__1__u64__ret_void,@function
standard__io__console__print__1__u64__ret_void: # @standard__io__console__print__1__u64__ret_void
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbx
	.cfi_def_cfa_offset 16
	subq	$32, %rsp
	.cfi_def_cfa_offset 48
	.cfi_offset %rbx, -16
	movq	%rdi, (%rsp)
	leaq	11(%rsp), %rbx
	movq	%rbx, %rsi
	callq	u64str__2__u64__byte_ptr1__ret_u64@PLT
	movq	%rbx, %rdi
	callq	standard__io__console__print__1__noopstr__ret_void@PLT
	addq	$32, %rsp
	.cfi_def_cfa_offset 16
	popq	%rbx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end78:
	.size	standard__io__console__print__1__u64__ret_void, .Lfunc_end78-standard__io__console__print__1__u64__ret_void
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__console__print__1__float__ret_void # -- Begin function standard__io__console__print__1__float__ret_void
	.p2align	4, 0x90
	.type	standard__io__console__print__1__float__ret_void,@function
standard__io__console__print__1__float__ret_void: # @standard__io__console__print__1__float__ret_void
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbx
	.cfi_def_cfa_offset 16
	subq	$272, %rsp                      # imm = 0x110
	.cfi_def_cfa_offset 288
	.cfi_offset %rbx, -16
	vmovss	%xmm0, 12(%rsp)
	leaq	16(%rsp), %rbx
	movq	%rbx, %rdi
	movl	$5, %esi
	callq	float2str__3__float__byte_ptr1__i32__ret_i32@PLT
	movq	%rbx, %rdi
	callq	standard__io__console__print__1__noopstr__ret_void@PLT
	addq	$272, %rsp                      # imm = 0x110
	.cfi_def_cfa_offset 16
	popq	%rbx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end79:
	.size	standard__io__console__print__1__float__ret_void, .Lfunc_end79-standard__io__console__print__1__float__ret_void
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__console__print__2__float__int__ret_void # -- Begin function standard__io__console__print__2__float__int__ret_void
	.p2align	4, 0x90
	.type	standard__io__console__print__2__float__int__ret_void,@function
standard__io__console__print__2__float__int__ret_void: # @standard__io__console__print__2__float__int__ret_void
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbx
	.cfi_def_cfa_offset 16
	subq	$272, %rsp                      # imm = 0x110
	.cfi_def_cfa_offset 288
	.cfi_offset %rbx, -16
	movl	%edi, %esi
	vmovss	%xmm0, 12(%rsp)
	movl	%edi, 8(%rsp)
	leaq	16(%rsp), %rbx
	movq	%rbx, %rdi
	callq	float2str__3__float__byte_ptr1__i32__ret_i32@PLT
	movq	%rbx, %rdi
	callq	standard__io__console__print__1__noopstr__ret_void@PLT
	addq	$272, %rsp                      # imm = 0x110
	.cfi_def_cfa_offset 16
	popq	%rbx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end80:
	.size	standard__io__console__print__2__float__int__ret_void, .Lfunc_end80-standard__io__console__print__2__float__int__ret_void
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__console__print__0__ret_void # -- Begin function standard__io__console__print__0__ret_void
	.p2align	4, 0x90
	.type	standard__io__console__print__0__ret_void,@function
standard__io__console__print__0__ret_void: # @standard__io__console__print__0__ret_void
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rax
	.cfi_def_cfa_offset 16
	movb	$10, 7(%rsp)
	leaq	7(%rsp), %rdi
	movl	$1, %esi
	callq	standard__io__console__nix_print__2__byte_ptr1__int__ret_void@PLT
	popq	%rax
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end81:
	.size	standard__io__console__print__0__ret_void, .Lfunc_end81-standard__io__console__print__0__ret_void
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__file__open__3__byte_ptr1__i32__i32__ret_i64 # -- Begin function standard__io__file__open__3__byte_ptr1__i32__i32__ret_i64
	.p2align	4, 0x90
	.type	standard__io__file__open__3__byte_ptr1__i32__i32__ret_i64,@function
standard__io__file__open__3__byte_ptr1__i32__i32__ret_i64: # @standard__io__file__open__3__byte_ptr1__i32__i32__ret_i64
	.cfi_startproc
# %bb.0:                                # %entry
	movl	%edx, %r8d
	movl	%esi, %r9d
	movq	%rdi, %r10
	movq	%rdi, -8(%rsp)
	movl	%esi, -12(%rsp)
	movl	%edx, -16(%rsp)
	movq	$-1, -32(%rsp)
	leaq	-32(%rsp), %rax
	movq	%rax, -24(%rsp)
	#APP
	movq	$2, %rax
	movq	%r10, %rdi
	movl	%r9d, %esi
	movl	%r8d, %edx
	syscall
	movq	%rax, -24(%rsp)
	#NO_APP
	movq	-32(%rsp), %rax
	retq
.Lfunc_end82:
	.size	standard__io__file__open__3__byte_ptr1__i32__i32__ret_i64, .Lfunc_end82-standard__io__file__open__3__byte_ptr1__i32__i32__ret_i64
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__file__read__3__i64__byte_ptr1__u64__ret_i64 # -- Begin function standard__io__file__read__3__i64__byte_ptr1__u64__ret_i64
	.p2align	4, 0x90
	.type	standard__io__file__read__3__i64__byte_ptr1__u64__ret_i64,@function
standard__io__file__read__3__i64__byte_ptr1__u64__ret_i64: # @standard__io__file__read__3__i64__byte_ptr1__u64__ret_i64
	.cfi_startproc
# %bb.0:                                # %entry
	movq	%rdx, %r8
	movq	%rsi, %r9
	movq	%rdi, %r10
	movq	%rdi, -8(%rsp)
	movq	%rsi, -16(%rsp)
	movq	%rdx, -24(%rsp)
	movq	$0, -40(%rsp)
	leaq	-40(%rsp), %rax
	movq	%rax, -32(%rsp)
	#APP
	movq	$0, %rax
	movq	%r10, %rdi
	movq	%r9, %rsi
	movq	%r8, %rdx
	syscall
	movq	%rax, -32(%rsp)
	#NO_APP
	movq	-40(%rsp), %rax
	retq
.Lfunc_end83:
	.size	standard__io__file__read__3__i64__byte_ptr1__u64__ret_i64, .Lfunc_end83-standard__io__file__read__3__i64__byte_ptr1__u64__ret_i64
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__file__write__3__i64__byte_ptr1__u64__ret_i64 # -- Begin function standard__io__file__write__3__i64__byte_ptr1__u64__ret_i64
	.p2align	4, 0x90
	.type	standard__io__file__write__3__i64__byte_ptr1__u64__ret_i64,@function
standard__io__file__write__3__i64__byte_ptr1__u64__ret_i64: # @standard__io__file__write__3__i64__byte_ptr1__u64__ret_i64
	.cfi_startproc
# %bb.0:                                # %entry
	movq	%rdx, %r8
	movq	%rsi, %r9
	movq	%rdi, %r10
	movq	%rdi, -8(%rsp)
	movq	%rsi, -16(%rsp)
	movq	%rdx, -24(%rsp)
	movq	$0, -40(%rsp)
	leaq	-40(%rsp), %rax
	movq	%rax, -32(%rsp)
	#APP
	movq	$1, %rax
	movq	%r10, %rdi
	movq	%r9, %rsi
	movq	%r8, %rdx
	syscall
	movq	%rax, -32(%rsp)
	#NO_APP
	movq	-40(%rsp), %rax
	retq
.Lfunc_end84:
	.size	standard__io__file__write__3__i64__byte_ptr1__u64__ret_i64, .Lfunc_end84-standard__io__file__write__3__i64__byte_ptr1__u64__ret_i64
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__file__close__1__i64__ret_i32 # -- Begin function standard__io__file__close__1__i64__ret_i32
	.p2align	4, 0x90
	.type	standard__io__file__close__1__i64__ret_i32,@function
standard__io__file__close__1__i64__ret_i32: # @standard__io__file__close__1__i64__ret_i32
	.cfi_startproc
# %bb.0:                                # %entry
	movq	%rdi, %r8
	movq	%rdi, -8(%rsp)
	movq	$0, -24(%rsp)
	leaq	-24(%rsp), %rax
	movq	%rax, -16(%rsp)
	#APP
	movq	$3, %rax
	movq	%r8, %rdi
	syscall
	movq	%rax, -16(%rsp)
	#NO_APP
	movl	-24(%rsp), %eax
	retq
.Lfunc_end85:
	.size	standard__io__file__close__1__i64__ret_i32, .Lfunc_end85-standard__io__file__close__1__i64__ret_i32
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__file__open_read__1__byte_ptr1__ret_i64 # -- Begin function standard__io__file__open_read__1__byte_ptr1__ret_i64
	.p2align	4, 0x90
	.type	standard__io__file__open_read__1__byte_ptr1__ret_i64,@function
standard__io__file__open_read__1__byte_ptr1__ret_i64: # @standard__io__file__open_read__1__byte_ptr1__ret_i64
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rax
	.cfi_def_cfa_offset 16
	movq	%rdi, (%rsp)
	xorl	%esi, %esi
	xorl	%edx, %edx
	callq	standard__io__file__open__3__byte_ptr1__i32__i32__ret_i64@PLT
	popq	%rcx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end86:
	.size	standard__io__file__open_read__1__byte_ptr1__ret_i64, .Lfunc_end86-standard__io__file__open_read__1__byte_ptr1__ret_i64
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__file__open_write__1__byte_ptr1__ret_i64 # -- Begin function standard__io__file__open_write__1__byte_ptr1__ret_i64
	.p2align	4, 0x90
	.type	standard__io__file__open_write__1__byte_ptr1__ret_i64,@function
standard__io__file__open_write__1__byte_ptr1__ret_i64: # @standard__io__file__open_write__1__byte_ptr1__ret_i64
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rax
	.cfi_def_cfa_offset 16
	movq	%rdi, (%rsp)
	movl	$577, %esi                      # imm = 0x241
	movl	$1604, %edx                     # imm = 0x644
	callq	standard__io__file__open__3__byte_ptr1__i32__i32__ret_i64@PLT
	popq	%rcx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end87:
	.size	standard__io__file__open_write__1__byte_ptr1__ret_i64, .Lfunc_end87-standard__io__file__open_write__1__byte_ptr1__ret_i64
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__file__open_append__1__byte_ptr1__ret_i64 # -- Begin function standard__io__file__open_append__1__byte_ptr1__ret_i64
	.p2align	4, 0x90
	.type	standard__io__file__open_append__1__byte_ptr1__ret_i64,@function
standard__io__file__open_append__1__byte_ptr1__ret_i64: # @standard__io__file__open_append__1__byte_ptr1__ret_i64
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rax
	.cfi_def_cfa_offset 16
	movq	%rdi, (%rsp)
	movl	$1089, %esi                     # imm = 0x441
	movl	$1604, %edx                     # imm = 0x644
	callq	standard__io__file__open__3__byte_ptr1__i32__i32__ret_i64@PLT
	popq	%rcx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end88:
	.size	standard__io__file__open_append__1__byte_ptr1__ret_i64, .Lfunc_end88-standard__io__file__open_append__1__byte_ptr1__ret_i64
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__file__open_read_write__1__byte_ptr1__ret_i64 # -- Begin function standard__io__file__open_read_write__1__byte_ptr1__ret_i64
	.p2align	4, 0x90
	.type	standard__io__file__open_read_write__1__byte_ptr1__ret_i64,@function
standard__io__file__open_read_write__1__byte_ptr1__ret_i64: # @standard__io__file__open_read_write__1__byte_ptr1__ret_i64
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rax
	.cfi_def_cfa_offset 16
	movq	%rdi, (%rsp)
	movl	$66, %esi
	movl	$1604, %edx                     # imm = 0x644
	callq	standard__io__file__open__3__byte_ptr1__i32__i32__ret_i64@PLT
	popq	%rcx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end89:
	.size	standard__io__file__open_read_write__1__byte_ptr1__ret_i64, .Lfunc_end89-standard__io__file__open_read_write__1__byte_ptr1__ret_i64
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__file__read32__3__i64__byte_ptr1__u32__ret_i32 # -- Begin function standard__io__file__read32__3__i64__byte_ptr1__u32__ret_i32
	.p2align	4, 0x90
	.type	standard__io__file__read32__3__i64__byte_ptr1__u32__ret_i32,@function
standard__io__file__read32__3__i64__byte_ptr1__u32__ret_i32: # @standard__io__file__read32__3__i64__byte_ptr1__u32__ret_i32
	.cfi_startproc
# %bb.0:                                # %entry
	subq	$40, %rsp
	.cfi_def_cfa_offset 48
	movq	%rdi, 32(%rsp)
	movq	%rsi, 24(%rsp)
	movl	%edx, 12(%rsp)
	movl	%edx, %edx
	callq	standard__io__file__read__3__i64__byte_ptr1__u64__ret_i64@PLT
	movq	%rax, 16(%rsp)
                                        # kill: def $eax killed $eax killed $rax
	addq	$40, %rsp
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end90:
	.size	standard__io__file__read32__3__i64__byte_ptr1__u32__ret_i32, .Lfunc_end90-standard__io__file__read32__3__i64__byte_ptr1__u32__ret_i32
	.cfi_endproc
                                        # -- End function
	.globl	standard__io__file__write32__3__i64__byte_ptr1__u32__ret_i32 # -- Begin function standard__io__file__write32__3__i64__byte_ptr1__u32__ret_i32
	.p2align	4, 0x90
	.type	standard__io__file__write32__3__i64__byte_ptr1__u32__ret_i32,@function
standard__io__file__write32__3__i64__byte_ptr1__u32__ret_i32: # @standard__io__file__write32__3__i64__byte_ptr1__u32__ret_i32
	.cfi_startproc
# %bb.0:                                # %entry
	subq	$40, %rsp
	.cfi_def_cfa_offset 48
	movq	%rdi, 32(%rsp)
	movq	%rsi, 24(%rsp)
	movl	%edx, 12(%rsp)
	movl	%edx, %edx
	callq	standard__io__file__write__3__i64__byte_ptr1__u64__ret_i64@PLT
	movq	%rax, 16(%rsp)
                                        # kill: def $eax killed $eax killed $rax
	addq	$40, %rsp
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end91:
	.size	standard__io__file__write32__3__i64__byte_ptr1__u32__ret_i32, .Lfunc_end91-standard__io__file__write32__3__i64__byte_ptr1__u32__ret_i32
	.cfi_endproc
                                        # -- End function
	.globl	main                            # -- Begin function main
	.p2align	4, 0x90
	.type	main,@function
main:                                   # @main
	.cfi_startproc
# %bb.0:                                # %entry
	subq	$40, %rsp
	.cfi_def_cfa_offset 48
	movabsq	$8022916924116329800, %rax      # imm = 0x6F57206F6C6C6548
	movq	%rax, 26(%rsp)
	movl	$560229490, 34(%rsp)            # imm = 0x21646C72
	movw	$10, 38(%rsp)
	movq	%rax, 12(%rsp)
	movl	$560229490, 20(%rsp)            # imm = 0x21646C72
	movw	$10, 24(%rsp)
	leaq	12(%rsp), %rdi
	callq	standard__io__console__print__1__noopstr__ret_void@PLT
	xorl	%eax, %eax
	addq	$40, %rsp
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end92:
	.size	main, .Lfunc_end92-main
	.cfi_endproc
                                        # -- End function
	.globl	FRTStartup                      # -- Begin function FRTStartup
	.p2align	4, 0x90
	.type	FRTStartup,@function
FRTStartup:                             # @FRTStartup
	.cfi_startproc
# %bb.0:                                # %entry
	subq	$40, %rsp
	.cfi_def_cfa_offset 48
	movq	$0, 32(%rsp)
	movq	$0, 24(%rsp)
	leaq	32(%rsp), %rax
	movq	%rax, 16(%rsp)
	leaq	24(%rsp), %rax
	movq	%rax, 8(%rsp)
	#APP
	movq	%rdi, 16(%rsp)
	movq	%rsi, 8(%rsp)
	#NO_APP
	callq	main@PLT
	movl	%eax, 4(%rsp)
	xorl	%edi, %edi
	callq	exit@PLT
	movl	4(%rsp), %eax
	addq	$40, %rsp
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end93:
	.size	FRTStartup, .Lfunc_end93-FRTStartup
	.cfi_endproc
                                        # -- End function
	.globl	_start                          # -- Begin function _start
	.p2align	4, 0x90
	.type	_start,@function
_start:                                 # @_start
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rax
	.cfi_def_cfa_offset 16
	callq	FRTStartup@PLT
	popq	%rcx
	.cfi_def_cfa_offset 8
	retq
.Lfunc_end94:
	.size	_start, .Lfunc_end94-_start
	.cfi_endproc
                                        # -- End function
	.type	standard__io__file__SEEK_SET,@object # @standard__io__file__SEEK_SET
	.local	standard__io__file__SEEK_SET
	.comm	standard__io__file__SEEK_SET,4,4
	.type	standard__io__file__SEEK_CUR,@object # @standard__io__file__SEEK_CUR
	.data
	.p2align	2, 0x0
standard__io__file__SEEK_CUR:
	.long	1                               # 0x1
	.size	standard__io__file__SEEK_CUR, 4

	.type	standard__io__file__SEEK_END,@object # @standard__io__file__SEEK_END
	.p2align	2, 0x0
standard__io__file__SEEK_END:
	.long	2                               # 0x2
	.size	standard__io__file__SEEK_END, 4

	.type	OS_UNKNOWN,@object              # @OS_UNKNOWN
	.local	OS_UNKNOWN
	.comm	OS_UNKNOWN,4,4
	.type	OS_WINDOWS,@object              # @OS_WINDOWS
	.p2align	2, 0x0
OS_WINDOWS:
	.long	1                               # 0x1
	.size	OS_WINDOWS, 4

	.type	OS_LINUX,@object                # @OS_LINUX
	.p2align	2, 0x0
OS_LINUX:
	.long	2                               # 0x2
	.size	OS_LINUX, 4

	.type	OS_MACOS,@object                # @OS_MACOS
	.p2align	2, 0x0
OS_MACOS:
	.long	3                               # 0x3
	.size	OS_MACOS, 4

	.section	".note.GNU-stack","",@progbits
