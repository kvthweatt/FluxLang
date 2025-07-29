; ModuleID = "flux_module"
target triple = "x86_64-pc-linux-gnu"
target datalayout = ""

define i32 @"main"()
{
entry:
  %"a" = alloca i32
  store i32 0, i32* %"a"
  %"b" = alloca i32
  store i32 1, i32* %"b"
  %"a.1" = load i32, i32* %"a"
  %"b.1" = load i32, i32* %"b"
  %".4" = icmp eq i32 %"a.1", %"b.1"
  br i1 %".4", label %"assert.pass", label %"assert.fail"
assert.pass:
  ret i32 0
assert.fail:
  %".6" = getelementptr inbounds [7 x i8], [7 x i8]* @"assert_msg", i32 0, i32 0
  %".7" = call i32 @"puts"(i8* %".6")
  call void @"abort"()
  unreachable
}

@"assert_msg" = internal constant [7 x i8] c"a != b\0a"
declare i32 @"puts"(i8* %".1")

declare void @"abort"()
