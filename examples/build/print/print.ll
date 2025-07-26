; ModuleID = "flux_module"
target triple = "x86_64-pc-linux-gnu"
target datalayout = ""

define void @"print"(i8 %"str")
{
entry:
  %"str.addr" = alloca i8
  store i8 %"str", i8* %"str.addr"
  ret void
}

define i32 @"main"()
{
entry:
  call void @"print"(i8 115)
  ret i32 0
}
