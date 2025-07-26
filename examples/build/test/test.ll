; ModuleID = "flux_module"
target triple = "x86_64-pc-linux-gnu"
target datalayout = ""

@"a" = internal global i32 0
define i32 @"main"()
{
entry:
  %"a" = load i32, i32* @"a"
  switch i32 %"a", label %"switch_default" [i32 0, label %"case_0"]
case_0:
  store i32 1, i32* @"a"
  br label %"switch_default"
switch_default:
  %".5" = sub i32 0, 1
  store i32 %".5", i32* @"a"
  br label %"switch_default"
switch_merge:
  %"a.1" = load i32, i32* @"a"
  ret i32 %"a.1"
}
