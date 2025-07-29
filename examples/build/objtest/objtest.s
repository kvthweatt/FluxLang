	.text
	.file	"objtest.ll"
	.globl	main                            # -- Begin function main
	.p2align	4, 0x90
	.type	main,@function
main:                                   # @main
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rax
	.cfi_def_cfa_offset 16
	movl	$0, 4(%rsp)
	movl	$1, (%rsp)
	movb	$1, %al
	testb	%al, %al
	jne	.LBB0_2
# %bb.1:                                # %assert.pass
	xorl	%eax, %eax
	popq	%rcx
	.cfi_def_cfa_offset 8
	retq
.LBB0_2:                                # %assert.fail
	.cfi_def_cfa_offset 16
	movl	$assert_msg, %edi
	callq	puts@PLT
	callq	abort@PLT
.Lfunc_end0:
	.size	main, .Lfunc_end0-main
	.cfi_endproc
                                        # -- End function
	.type	assert_msg,@object              # @assert_msg
	.section	.rodata,"a",@progbits
assert_msg:
	.ascii	"a != b\n"
	.size	assert_msg, 7

	.section	".note.GNU-stack","",@progbits
