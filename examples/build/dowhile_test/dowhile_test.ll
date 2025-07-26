; ModuleID = "flux_module"
target triple = "x86_64-pc-linux-gnu"
target datalayout = ""

@"a" = internal global i32 0
@"b" = internal global i32 0
define i32 @"main"()
{
entry:
  br label %"dowhile.body"
dowhile.body:
  %"a" = load i32, i32* @"a"
  %".3" = add i32 %"a", 1
  br label %"dowhile.cond"
dowhile.cond:
  %".5" = icmp sge i32 %".3", 10
  br i1 %".5", label %"dowhile.body", label %"dowhile.end"
dowhile.end:
  ret i32 %".3"
}
