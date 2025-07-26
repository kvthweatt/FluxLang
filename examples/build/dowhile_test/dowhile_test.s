	.text
	.file	"dowhile_test.ll"
	.globl	main                            # -- Begin function main
	.p2align	4, 0x90
	.type	main,@function
main:                                   # @main
	.cfi_startproc
# %bb.0:                                # %entry
	movl	a(%rip), %eax
	incl	%eax
	.p2align	4, 0x90
.LBB0_1:                                # %dowhile.cond
                                        # =>This Inner Loop Header: Depth=1
	cmpl	$9, %eax
	jg	.LBB0_1
# %bb.2:                                # %dowhile.end
	retq
.Lfunc_end0:
	.size	main, .Lfunc_end0-main
	.cfi_endproc
                                        # -- End function
	.type	a,@object                       # @a
	.local	a
	.comm	a,4,4
	.type	b,@object                       # @b
	.local	b
	.comm	b,4,4
	.section	".note.GNU-stack","",@progbits
