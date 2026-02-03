; ModuleID = "flux_module"
target triple = "x86_64-pc-windows-msvc"
target datalayout = "e-m:w-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"

%"string" = type {i8*}
define void @"__static_init"()
{
entry:
  ret void
}

define i16 @"standard__types__bswap16__1__u16__ret_u16"(i16 %"value")
{
entry:
  %"value.addr" = alloca i16
  store i16 %"value", i16* %"value.addr"
  %"value.1" = load i16, i16* %"value.addr"
  %".4" = zext i16 %"value.1" to i32
  %".5" = and i32 %".4", 255
  %".6" = shl i32 %".5", 8
  %".7" = trunc i32 %".6" to i16
  %"value.2" = load i16, i16* %"value.addr"
  %".8" = trunc i32 8 to i16
  %".9" = ashr i16 %"value.2", %".8"
  %".10" = zext i16 %".9" to i32
  %".11" = and i32 %".10", 255
  %".12" = trunc i32 %".11" to i16
  %".13" = or i16 %".7", %".12"
  ret i16 %".13"
}

define i32 @"standard__types__bswap32__1__u32__ret_u32"(i32 %"value")
{
entry:
  %"value.addr" = alloca i32
  store i32 %"value", i32* %"value.addr"
  %"value.1" = load i32, i32* %"value.addr"
  %".4" = and i32 %"value.1", 255
  %".5" = shl i32 %".4", 24
  %"value.2" = load i32, i32* %"value.addr"
  %".6" = and i32 %"value.2", 65280
  %".7" = shl i32 %".6", 8
  %".8" = or i32 %".5", %".7"
  %"value.3" = load i32, i32* %"value.addr"
  %".9" = ashr i32 %"value.3", 8
  %".10" = and i32 %".9", 65280
  %".11" = or i32 %".8", %".10"
  %"value.4" = load i32, i32* %"value.addr"
  %".12" = ashr i32 %"value.4", 24
  %".13" = and i32 %".12", 255
  %".14" = or i32 %".11", %".13"
  ret i32 %".14"
}

define i64 @"standard__types__bswap64__1__u64__ret_u64"(i64 %"value")
{
entry:
  %"value.addr" = alloca i64
  store i64 %"value", i64* %"value.addr"
  %"value.1" = load i64, i64* %"value.addr"
  %".4" = zext i32 255 to i64
  %".5" = and i64 %"value.1", %".4"
  %".6" = zext i32 56 to i64
  %".7" = shl i64 %".5", %".6"
  %"value.2" = load i64, i64* %"value.addr"
  %".8" = zext i32 65280 to i64
  %".9" = and i64 %"value.2", %".8"
  %".10" = zext i32 40 to i64
  %".11" = shl i64 %".9", %".10"
  %".12" = or i64 %".7", %".11"
  %"value.3" = load i64, i64* %"value.addr"
  %".13" = zext i32 16711680 to i64
  %".14" = and i64 %"value.3", %".13"
  %".15" = zext i32 24 to i64
  %".16" = shl i64 %".14", %".15"
  %".17" = or i64 %".12", %".16"
  %"value.4" = load i64, i64* %"value.addr"
  %".18" = and i64 %"value.4", 4278190080
  %".19" = zext i32 8 to i64
  %".20" = shl i64 %".18", %".19"
  %".21" = or i64 %".17", %".20"
  %"value.5" = load i64, i64* %"value.addr"
  %".22" = zext i32 8 to i64
  %".23" = ashr i64 %"value.5", %".22"
  %".24" = and i64 %".23", 4278190080
  %".25" = or i64 %".21", %".24"
  %"value.6" = load i64, i64* %"value.addr"
  %".26" = zext i32 24 to i64
  %".27" = ashr i64 %"value.6", %".26"
  %".28" = zext i32 16711680 to i64
  %".29" = and i64 %".27", %".28"
  %".30" = or i64 %".25", %".29"
  %"value.7" = load i64, i64* %"value.addr"
  %".31" = zext i32 40 to i64
  %".32" = ashr i64 %"value.7", %".31"
  %".33" = zext i32 65280 to i64
  %".34" = and i64 %".32", %".33"
  %".35" = or i64 %".30", %".34"
  %"value.8" = load i64, i64* %"value.addr"
  %".36" = zext i32 56 to i64
  %".37" = ashr i64 %"value.8", %".36"
  %".38" = zext i32 255 to i64
  %".39" = and i64 %".37", %".38"
  %".40" = or i64 %".35", %".39"
  ret i64 %".40"
}

define i16 @"standard__types__ntoh16__1__be16__ret_le16"(i16 %"net_value")
{
entry:
  %"net_value.addr" = alloca i16
  store i16 %"net_value", i16* %"net_value.addr"
  %"net_value.1" = load i16, i16* %"net_value.addr"
  %".4" = call i16 @"standard__types__bswap16__1__u16__ret_u16"(i16 %"net_value.1")
  ret i16 %".4"
}

define i32 @"standard__types__ntoh32__1__be32__ret_le32"(i32 %"net_value")
{
entry:
  %"net_value.addr" = alloca i32
  store i32 %"net_value", i32* %"net_value.addr"
  %"net_value.1" = load i32, i32* %"net_value.addr"
  %".4" = call i32 @"standard__types__bswap32__1__u32__ret_u32"(i32 %"net_value.1")
  ret i32 %".4"
}

define i16 @"standard__types__hton16__1__le16__ret_be16"(i16 %"host_value")
{
entry:
  %"host_value.addr" = alloca i16
  store i16 %"host_value", i16* %"host_value.addr"
  %"host_value.1" = load i16, i16* %"host_value.addr"
  %".4" = call i16 @"standard__types__bswap16__1__u16__ret_u16"(i16 %"host_value.1")
  ret i16 %".4"
}

define i32 @"standard__types__hton32__1__le32__ret_be32"(i32 %"host_value")
{
entry:
  %"host_value.addr" = alloca i32
  store i32 %"host_value", i32* %"host_value.addr"
  %"host_value.1" = load i32, i32* %"host_value.addr"
  %".4" = call i32 @"standard__types__bswap32__1__u32__ret_u32"(i32 %"host_value.1")
  ret i32 %".4"
}

define i1 @"standard__types__bit_test__2__u32__u32__ret_bool"(i32 %"value", i32 %"bit")
{
entry:
  %"value.addr" = alloca i32
  store i32 %"value", i32* %"value.addr"
  %"bit.addr" = alloca i32
  store i32 %"bit", i32* %"bit.addr"
  %"value.1" = load i32, i32* %"value.addr"
  %"bit.1" = load i32, i32* %"bit.addr"
  %".6" = shl i32 1, %"bit.1"
  %".7" = and i32 %"value.1", %".6"
  %".8" = icmp ne i32 %".7", 0
  ret i1 %".8"
}

define i64 @"standard__types__align_up__2__u64__u64__ret_u64"(i64 %"value", i64 %"alignment")
{
entry:
  %"value.addr" = alloca i64
  store i64 %"value", i64* %"value.addr"
  %"alignment.addr" = alloca i64
  store i64 %"alignment", i64* %"alignment.addr"
  %"value.1" = load i64, i64* %"value.addr"
  %"alignment.1" = load i64, i64* %"alignment.addr"
  %".6" = add i64 %"value.1", %"alignment.1"
  %".7" = zext i32 1 to i64
  %".8" = sub i64 %".6", %".7"
  %"alignment.2" = load i64, i64* %"alignment.addr"
  %".9" = zext i32 1 to i64
  %".10" = sub i64 %"alignment.2", %".9"
  %".11" = and i64 %".8", %".10"
  ret i64 %".11"
}

define i64 @"standard__types__align_down__2__u64__u64__ret_u64"(i64 %"value", i64 %"alignment")
{
entry:
  %"value.addr" = alloca i64
  store i64 %"value", i64* %"value.addr"
  %"alignment.addr" = alloca i64
  store i64 %"alignment", i64* %"alignment.addr"
  %"value.1" = load i64, i64* %"value.addr"
  %"alignment.1" = load i64, i64* %"alignment.addr"
  %".6" = zext i32 1 to i64
  %".7" = sub i64 %"alignment.1", %".6"
  %".8" = and i64 %"value.1", %".7"
  ret i64 %".8"
}

define i1 @"standard__types__is_aligned__2__u64__u64__ret_bool"(i64 %"value", i64 %"alignment")
{
entry:
  %"value.addr" = alloca i64
  store i64 %"value", i64* %"value.addr"
  %"alignment.addr" = alloca i64
  store i64 %"alignment", i64* %"alignment.addr"
  %"value.1" = load i64, i64* %"value.addr"
  %"alignment.1" = load i64, i64* %"alignment.addr"
  %".6" = zext i32 1 to i64
  %".7" = sub i64 %"alignment.1", %".6"
  %".8" = and i64 %"value.1", %".7"
  %".9" = zext i32 0 to i64
  %".10" = icmp eq i64 %".8", %".9"
  ret i1 %".10"
}

declare external i8* @"malloc"(i64 %"size")

declare external i8* @"memcpy"(i8* %"dest", i8* %"src.1", i64 %"n.1")

declare external void @"free"(i8* %"ptr")

declare external i8* @"calloc"(i64 %"num", i64 %"size")

declare external i8* @"realloc"(i8* %"ptr", i64 %"size")

declare external i8* @"memmove"(i8* %"dest", i8* %"src", i64 %"n")

declare external i8* @"memset"(i8* %"ptr", i32 %"value", i64 %"n")

declare external i32 @"memcmp"(i8* %"ptr1", i8* %"ptr2", i64 %"n")

declare external i64 @"strlen"(i8* %"str")

declare external i8* @"strcpy"(i8* %"dest", i8* %"src")

declare external i8* @"strncpy"(i8* %"dest.1", i8* %"src.1", i64 %"n.1")

declare external i8* @"strcat"(i8* %"dest.1", i8* %"src.1")

declare external i8* @"strncat"(i8* %"dest.1", i8* %"src.1", i64 %"n.1")

declare external i32 @"strcmp"(i8* %"x", i8* %"y")

declare external i32 @"strncmp"(i8* %"s1.1", i8* %"s2.1", i64 %"n.1")

declare external i8* @"strchr"(i8* %"str.1", i32 %"ch.1")

declare external i8* @"strstr"(i8* %"haystack.1", i8* %"needle.1")

declare external void @"abort"()

declare external void @"exit"(i32 %"code")

declare external i32 @"atexit"(i8* %"null")

declare external void @"printf"(i8* %"x", i8* %"y")

define i32 @"strlen__1__byte_ptr1__ret_int"(i8* %"ps")
{
entry:
  %"ps.addr" = alloca i8*
  store i8* %"ps", i8** %"ps.addr"
  %"c" = alloca i32
  store i32 0, i32* %"c"
  br label %"while.cond"
while.cond:
  br i1 true, label %"while.body", label %"while.end"
while.body:
  %"ch" = alloca i8*
  %"ps.1" = load i8*, i8** %"ps.addr"
  %"ptr_inc" = getelementptr i8, i8* %"ps.1", i32 1
  store i8* %"ptr_inc", i8** %"ps.addr"
  store i8* %"ps.1", i8** %"ch"
  %"ch.1" = load i8*, i8** %"ch"
  %"deref" = load i8, i8* %"ch.1"
  %".9" = zext i8 %"deref" to i32
  %".10" = icmp eq i32 %".9", 0
  br i1 %".10", label %"then", label %"else"
while.end:
  %"c.2" = load i32, i32* %"c"
  ret i32 %"c.2"
then:
  br label %"while.end"
else:
  br label %"ifcont"
ifcont:
  %"c.1" = load i32, i32* %"c"
  %".14" = add i32 %"c.1", 1
  store i32 %".14", i32* %"c"
  br label %"while.cond"
}

define i8* @"strcpy__2__noopstr__noopstr__ret_noopstr"(i8* %"dest", i8* %"src")
{
entry:
  %"dest.addr" = alloca i8*
  store i8* %"dest", i8** %"dest.addr"
  %"src.addr" = alloca i8*
  store i8* %"src", i8** %"src.addr"
  %"i" = alloca i64
  %".6" = sext i32 0 to i64
  store i64 %".6", i64* %"i"
  br label %"while.cond"
while.cond:
  %"src.1" = load i8*, i8** %"src.addr"
  %"i.1" = load i64, i64* %"i"
  %"idx_trunc" = trunc i64 %"i.1" to i32
  %"ptr_gep" = getelementptr inbounds i8, i8* %"src.1", i32 %"idx_trunc"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".9" = zext i8 %"ptr_load" to i32
  %".10" = icmp ne i32 %".9", 0
  br i1 %".10", label %"while.body", label %"while.end"
while.body:
  %"src.2" = load i8*, i8** %"src.addr"
  %"i.2" = load i64, i64* %"i"
  %"idx_trunc.1" = trunc i64 %"i.2" to i32
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"src.2", i32 %"idx_trunc.1"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %"dest.1" = load i8*, i8** %"dest.addr"
  %"i.3" = load i64, i64* %"i"
  %".12" = getelementptr inbounds i8, i8* %"dest.1", i64 %"i.3"
  %"src.3" = load i8*, i8** %"src.addr"
  %"i.4" = load i64, i64* %"i"
  %"idx_trunc.2" = trunc i64 %"i.4" to i32
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"src.3", i32 %"idx_trunc.2"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  store i8 %"ptr_load.2", i8* %".12"
  %"i.5" = load i64, i64* %"i"
  %".14" = add i64 %"i.5", 1
  store i64 %".14", i64* %"i"
  br label %"while.cond"
while.end:
  %".17" = trunc i32 0 to i8
  %"dest.2" = load i8*, i8** %"dest.addr"
  %"i.6" = load i64, i64* %"i"
  %".18" = getelementptr inbounds i8, i8* %"dest.2", i64 %"i.6"
  %".19" = trunc i32 0 to i8
  store i8 %".19", i8* %".18"
  %"dest.3" = load i8*, i8** %"dest.addr"
  ret i8* %"dest.3"
}

define i32 @"i32str__2__i32__byte_ptr1__ret_i32"(i32 %"value", i8* %"buffer")
{
entry:
  %"value.addr" = alloca i32
  store i32 %"value", i32* %"value.addr"
  %"buffer.addr" = alloca i8*
  store i8* %"buffer", i8** %"buffer.addr"
  %"value.1" = load i32, i32* %"value.addr"
  %".6" = icmp eq i32 %"value.1", 0
  br i1 %".6", label %"then", label %"else"
then:
  %".8" = trunc i32 48 to i8
  %"buffer.1" = load i8*, i8** %"buffer.addr"
  %".9" = getelementptr inbounds i8, i8* %"buffer.1", i32 0
  %".10" = trunc i32 48 to i8
  store i8 %".10", i8* %".9"
  %".12" = trunc i32 0 to i8
  %"buffer.2" = load i8*, i8** %"buffer.addr"
  %".13" = getelementptr inbounds i8, i8* %"buffer.2", i32 1
  %".14" = trunc i32 0 to i8
  store i8 %".14", i8* %".13"
  ret i32 1
else:
  br label %"ifcont"
ifcont:
  %"is_negative" = alloca i32
  store i32 0, i32* %"is_negative"
  %"value.2" = load i32, i32* %"value.addr"
  %".19" = icmp slt i32 %"value.2", 0
  br i1 %".19", label %"then.1", label %"else.1"
then.1:
  store i32 1, i32* %"is_negative"
  %"value.3" = load i32, i32* %"value.addr"
  %".22" = sub i32 0, %"value.3"
  store i32 %".22", i32* %"value.addr"
  br label %"ifcont.1"
else.1:
  br label %"ifcont.1"
ifcont.1:
  %"pos" = alloca i32
  store i32 0, i32* %"pos"
  %"temp" = alloca [32 x i8]
  br label %"while.cond"
while.cond:
  %"value.4" = load i32, i32* %"value.addr"
  %".28" = icmp sgt i32 %"value.4", 0
  br i1 %".28", label %"while.body", label %"while.end"
while.body:
  %"value.5" = load i32, i32* %"value.addr"
  %".30" = srem i32 %"value.5", 10
  %".31" = add i32 %".30", 48
  %".32" = trunc i32 %".31" to i8
  %"pos.1" = load i32, i32* %"pos"
  %".33" = getelementptr inbounds [32 x i8], [32 x i8]* %"temp", i1 0, i32 %"pos.1"
  %"value.6" = load i32, i32* %"value.addr"
  %".34" = srem i32 %"value.6", 10
  %".35" = add i32 %".34", 48
  %".36" = trunc i32 %".35" to i8
  store i8 %".36", i8* %".33"
  %"value.7" = load i32, i32* %"value.addr"
  %".38" = sdiv i32 %"value.7", 10
  store i32 %".38", i32* %"value.addr"
  %"pos.2" = load i32, i32* %"pos"
  %".40" = add i32 %"pos.2", 1
  store i32 %".40", i32* %"pos"
  br label %"while.cond"
while.end:
  %"write_pos" = alloca i32
  store i32 0, i32* %"write_pos"
  %"is_negative.1" = load i32, i32* %"is_negative"
  %".44" = icmp eq i32 %"is_negative.1", 1
  br i1 %".44", label %"then.2", label %"else.2"
then.2:
  %".46" = trunc i32 45 to i8
  %"buffer.3" = load i8*, i8** %"buffer.addr"
  %".47" = getelementptr inbounds i8, i8* %"buffer.3", i32 0
  %".48" = trunc i32 45 to i8
  store i8 %".48", i8* %".47"
  store i32 1, i32* %"write_pos"
  br label %"ifcont.2"
else.2:
  br label %"ifcont.2"
ifcont.2:
  %"i" = alloca i32
  %"pos.3" = load i32, i32* %"pos"
  %".53" = sub i32 %"pos.3", 1
  store i32 %".53", i32* %"i"
  br label %"while.cond.1"
while.cond.1:
  %"i.1" = load i32, i32* %"i"
  %".56" = icmp sge i32 %"i.1", 0
  br i1 %".56", label %"while.body.1", label %"while.end.1"
while.body.1:
  %"i.2" = load i32, i32* %"i"
  %"array_gep" = getelementptr inbounds [32 x i8], [32 x i8]* %"temp", i32 0, i32 %"i.2"
  %"array_load" = load i8, i8* %"array_gep"
  %"buffer.4" = load i8*, i8** %"buffer.addr"
  %"write_pos.1" = load i32, i32* %"write_pos"
  %".58" = getelementptr inbounds i8, i8* %"buffer.4", i32 %"write_pos.1"
  %"i.3" = load i32, i32* %"i"
  %"array_gep.1" = getelementptr inbounds [32 x i8], [32 x i8]* %"temp", i32 0, i32 %"i.3"
  %"array_load.1" = load i8, i8* %"array_gep.1"
  store i8 %"array_load.1", i8* %".58"
  %"write_pos.2" = load i32, i32* %"write_pos"
  %".60" = add i32 %"write_pos.2", 1
  store i32 %".60", i32* %"write_pos"
  %"i.4" = load i32, i32* %"i"
  %".62" = sub i32 %"i.4", 1
  store i32 %".62", i32* %"i"
  br label %"while.cond.1"
while.end.1:
  %".65" = trunc i32 0 to i8
  %"buffer.5" = load i8*, i8** %"buffer.addr"
  %"write_pos.3" = load i32, i32* %"write_pos"
  %".66" = getelementptr inbounds i8, i8* %"buffer.5", i32 %"write_pos.3"
  %".67" = trunc i32 0 to i8
  store i8 %".67", i8* %".66"
  %"write_pos.4" = load i32, i32* %"write_pos"
  ret i32 %"write_pos.4"
}

define i64 @"i64str__2__i64__byte_ptr1__ret_i64"(i64 %"value", i8* %"buffer")
{
entry:
  %"value.addr" = alloca i64
  store i64 %"value", i64* %"value.addr"
  %"buffer.addr" = alloca i8*
  store i8* %"buffer", i8** %"buffer.addr"
  %"value.1" = load i64, i64* %"value.addr"
  %".6" = sext i32 0 to i64
  %".7" = icmp eq i64 %"value.1", %".6"
  br i1 %".7", label %"then", label %"else"
then:
  %".9" = trunc i32 48 to i8
  %"buffer.1" = load i8*, i8** %"buffer.addr"
  %".10" = getelementptr inbounds i8, i8* %"buffer.1", i32 0
  %".11" = trunc i32 48 to i8
  store i8 %".11", i8* %".10"
  %".13" = trunc i32 0 to i8
  %"buffer.2" = load i8*, i8** %"buffer.addr"
  %".14" = getelementptr inbounds i8, i8* %"buffer.2", i32 1
  %".15" = trunc i32 0 to i8
  store i8 %".15", i8* %".14"
  %".17" = sext i32 1 to i64
  ret i64 %".17"
else:
  br label %"ifcont"
ifcont:
  %"is_negative" = alloca i64
  %".20" = sext i32 0 to i64
  store i64 %".20", i64* %"is_negative"
  %"value.2" = load i64, i64* %"value.addr"
  %".22" = sext i32 0 to i64
  %".23" = icmp slt i64 %"value.2", %".22"
  br i1 %".23", label %"then.1", label %"else.1"
then.1:
  %".25" = sext i32 1 to i64
  store i64 %".25", i64* %"is_negative"
  %"value.3" = load i64, i64* %"value.addr"
  %".27" = sub i64 0, %"value.3"
  store i64 %".27", i64* %"value.addr"
  br label %"ifcont.1"
else.1:
  br label %"ifcont.1"
ifcont.1:
  %"pos" = alloca i64
  %".31" = sext i32 0 to i64
  store i64 %".31", i64* %"pos"
  %"temp" = alloca [32 x i8]
  br label %"while.cond"
while.cond:
  %"value.4" = load i64, i64* %"value.addr"
  %".34" = sext i32 0 to i64
  %".35" = icmp sgt i64 %"value.4", %".34"
  br i1 %".35", label %"while.body", label %"while.end"
while.body:
  %"value.5" = load i64, i64* %"value.addr"
  %".37" = sext i32 10 to i64
  %".38" = srem i64 %"value.5", %".37"
  %".39" = sext i32 48 to i64
  %".40" = add i64 %".38", %".39"
  %".41" = trunc i64 %".40" to i8
  %"pos.1" = load i64, i64* %"pos"
  %".42" = getelementptr inbounds [32 x i8], [32 x i8]* %"temp", i1 0, i64 %"pos.1"
  %"value.6" = load i64, i64* %"value.addr"
  %".43" = sext i32 10 to i64
  %".44" = srem i64 %"value.6", %".43"
  %".45" = sext i32 48 to i64
  %".46" = add i64 %".44", %".45"
  %".47" = trunc i64 %".46" to i8
  store i8 %".47", i8* %".42"
  %"value.7" = load i64, i64* %"value.addr"
  %".49" = sext i32 10 to i64
  %".50" = sdiv i64 %"value.7", %".49"
  store i64 %".50", i64* %"value.addr"
  %"pos.2" = load i64, i64* %"pos"
  %".52" = add i64 %"pos.2", 1
  store i64 %".52", i64* %"pos"
  br label %"while.cond"
while.end:
  %"write_pos" = alloca i64
  %".55" = sext i32 0 to i64
  store i64 %".55", i64* %"write_pos"
  %"is_negative.1" = load i64, i64* %"is_negative"
  %".57" = sext i32 1 to i64
  %".58" = icmp eq i64 %"is_negative.1", %".57"
  br i1 %".58", label %"then.2", label %"else.2"
then.2:
  %".60" = trunc i32 45 to i8
  %"buffer.3" = load i8*, i8** %"buffer.addr"
  %".61" = getelementptr inbounds i8, i8* %"buffer.3", i32 0
  %".62" = trunc i32 45 to i8
  store i8 %".62", i8* %".61"
  %".64" = sext i32 1 to i64
  store i64 %".64", i64* %"write_pos"
  br label %"ifcont.2"
else.2:
  br label %"ifcont.2"
ifcont.2:
  %"i" = alloca i64
  %"pos.3" = load i64, i64* %"pos"
  %".68" = sext i32 1 to i64
  %".69" = sub i64 %"pos.3", %".68"
  store i64 %".69", i64* %"i"
  br label %"while.cond.1"
while.cond.1:
  %"i.1" = load i64, i64* %"i"
  %".72" = sext i32 0 to i64
  %".73" = icmp sge i64 %"i.1", %".72"
  br i1 %".73", label %"while.body.1", label %"while.end.1"
while.body.1:
  %"i.2" = load i64, i64* %"i"
  %"idx_trunc" = trunc i64 %"i.2" to i32
  %"array_gep" = getelementptr inbounds [32 x i8], [32 x i8]* %"temp", i32 0, i32 %"idx_trunc"
  %"array_load" = load i8, i8* %"array_gep"
  %"buffer.4" = load i8*, i8** %"buffer.addr"
  %"write_pos.1" = load i64, i64* %"write_pos"
  %".75" = getelementptr inbounds i8, i8* %"buffer.4", i64 %"write_pos.1"
  %"i.3" = load i64, i64* %"i"
  %"idx_trunc.1" = trunc i64 %"i.3" to i32
  %"array_gep.1" = getelementptr inbounds [32 x i8], [32 x i8]* %"temp", i32 0, i32 %"idx_trunc.1"
  %"array_load.1" = load i8, i8* %"array_gep.1"
  store i8 %"array_load.1", i8* %".75"
  %"write_pos.2" = load i64, i64* %"write_pos"
  %".77" = add i64 %"write_pos.2", 1
  store i64 %".77", i64* %"write_pos"
  %"i.4" = load i64, i64* %"i"
  %".79" = sub i64 %"i.4", 1
  store i64 %".79", i64* %"i"
  br label %"while.cond.1"
while.end.1:
  %".82" = trunc i32 0 to i8
  %"buffer.5" = load i8*, i8** %"buffer.addr"
  %"write_pos.3" = load i64, i64* %"write_pos"
  %".83" = getelementptr inbounds i8, i8* %"buffer.5", i64 %"write_pos.3"
  %".84" = trunc i32 0 to i8
  store i8 %".84", i8* %".83"
  %"write_pos.4" = load i64, i64* %"write_pos"
  ret i64 %"write_pos.4"
}

define i32 @"u32str__2__u32__byte_ptr1__ret_u32"(i32 %"value", i8* %"buffer")
{
entry:
  %"value.addr" = alloca i32
  store i32 %"value", i32* %"value.addr"
  %"buffer.addr" = alloca i8*
  store i8* %"buffer", i8** %"buffer.addr"
  %"value.1" = load i32, i32* %"value.addr"
  %".6" = icmp eq i32 %"value.1", 0
  br i1 %".6", label %"then", label %"else"
then:
  %".8" = trunc i32 48 to i8
  %"buffer.1" = load i8*, i8** %"buffer.addr"
  %".9" = getelementptr inbounds i8, i8* %"buffer.1", i32 0
  %".10" = trunc i32 48 to i8
  store i8 %".10", i8* %".9"
  %".12" = trunc i32 0 to i8
  %"buffer.2" = load i8*, i8** %"buffer.addr"
  %".13" = getelementptr inbounds i8, i8* %"buffer.2", i32 1
  %".14" = trunc i32 0 to i8
  store i8 %".14", i8* %".13"
  ret i32 1
else:
  br label %"ifcont"
ifcont:
  %"pos" = alloca i32
  store i32 0, i32* %"pos"
  %"temp" = alloca [32 x i8]
  br label %"while.cond"
while.cond:
  %"value.2" = load i32, i32* %"value.addr"
  %".20" = icmp sgt i32 %"value.2", 0
  br i1 %".20", label %"while.body", label %"while.end"
while.body:
  %"value.3" = load i32, i32* %"value.addr"
  %".22" = srem i32 %"value.3", 10
  %".23" = add i32 %".22", 48
  %".24" = trunc i32 %".23" to i8
  %"pos.1" = load i32, i32* %"pos"
  %".25" = getelementptr inbounds [32 x i8], [32 x i8]* %"temp", i1 0, i32 %"pos.1"
  %"value.4" = load i32, i32* %"value.addr"
  %".26" = srem i32 %"value.4", 10
  %".27" = add i32 %".26", 48
  %".28" = trunc i32 %".27" to i8
  store i8 %".28", i8* %".25"
  %"value.5" = load i32, i32* %"value.addr"
  %".30" = sdiv i32 %"value.5", 10
  store i32 %".30", i32* %"value.addr"
  %"pos.2" = load i32, i32* %"pos"
  %".32" = add i32 %"pos.2", 1
  store i32 %".32", i32* %"pos"
  br label %"while.cond"
while.end:
  %"write_pos" = alloca i32
  store i32 0, i32* %"write_pos"
  %"i" = alloca i32
  %"pos.3" = load i32, i32* %"pos"
  %".36" = sub i32 %"pos.3", 1
  store i32 %".36", i32* %"i"
  br label %"while.cond.1"
while.cond.1:
  %"i.1" = load i32, i32* %"i"
  %".39" = icmp sge i32 %"i.1", 0
  br i1 %".39", label %"while.body.1", label %"while.end.1"
while.body.1:
  %"i.2" = load i32, i32* %"i"
  %"array_gep" = getelementptr inbounds [32 x i8], [32 x i8]* %"temp", i32 0, i32 %"i.2"
  %"array_load" = load i8, i8* %"array_gep"
  %"buffer.3" = load i8*, i8** %"buffer.addr"
  %"write_pos.1" = load i32, i32* %"write_pos"
  %".41" = getelementptr inbounds i8, i8* %"buffer.3", i32 %"write_pos.1"
  %"i.3" = load i32, i32* %"i"
  %"array_gep.1" = getelementptr inbounds [32 x i8], [32 x i8]* %"temp", i32 0, i32 %"i.3"
  %"array_load.1" = load i8, i8* %"array_gep.1"
  store i8 %"array_load.1", i8* %".41"
  %"write_pos.2" = load i32, i32* %"write_pos"
  %".43" = add i32 %"write_pos.2", 1
  store i32 %".43", i32* %"write_pos"
  %"i.4" = load i32, i32* %"i"
  %".45" = sub i32 %"i.4", 1
  store i32 %".45", i32* %"i"
  br label %"while.cond.1"
while.end.1:
  %".48" = trunc i32 0 to i8
  %"buffer.4" = load i8*, i8** %"buffer.addr"
  %"write_pos.3" = load i32, i32* %"write_pos"
  %".49" = getelementptr inbounds i8, i8* %"buffer.4", i32 %"write_pos.3"
  %".50" = trunc i32 0 to i8
  store i8 %".50", i8* %".49"
  %"write_pos.4" = load i32, i32* %"write_pos"
  ret i32 %"write_pos.4"
}

define i64 @"u64str__2__u64__byte_ptr1__ret_u64"(i64 %"value", i8* %"buffer")
{
entry:
  %"value.addr" = alloca i64
  store i64 %"value", i64* %"value.addr"
  %"buffer.addr" = alloca i8*
  store i8* %"buffer", i8** %"buffer.addr"
  %"value.1" = load i64, i64* %"value.addr"
  %".6" = sext i32 0 to i64
  %".7" = icmp eq i64 %"value.1", %".6"
  br i1 %".7", label %"then", label %"else"
then:
  %".9" = trunc i32 48 to i8
  %"buffer.1" = load i8*, i8** %"buffer.addr"
  %".10" = getelementptr inbounds i8, i8* %"buffer.1", i32 0
  %".11" = trunc i32 48 to i8
  store i8 %".11", i8* %".10"
  %".13" = trunc i32 0 to i8
  %"buffer.2" = load i8*, i8** %"buffer.addr"
  %".14" = getelementptr inbounds i8, i8* %"buffer.2", i32 1
  %".15" = trunc i32 0 to i8
  store i8 %".15", i8* %".14"
  %".17" = sext i32 1 to i64
  ret i64 %".17"
else:
  br label %"ifcont"
ifcont:
  %"pos" = alloca i64
  %".20" = sext i32 0 to i64
  store i64 %".20", i64* %"pos"
  %"temp" = alloca [32 x i8]
  br label %"while.cond"
while.cond:
  %"value.2" = load i64, i64* %"value.addr"
  %".23" = sext i32 0 to i64
  %".24" = icmp ne i64 %"value.2", %".23"
  br i1 %".24", label %"while.body", label %"while.end"
while.body:
  %"value.3" = load i64, i64* %"value.addr"
  %".26" = sext i32 10 to i64
  %".27" = srem i64 %"value.3", %".26"
  %".28" = sext i32 48 to i64
  %".29" = add i64 %".27", %".28"
  %".30" = trunc i64 %".29" to i8
  %"pos.1" = load i64, i64* %"pos"
  %".31" = getelementptr inbounds [32 x i8], [32 x i8]* %"temp", i1 0, i64 %"pos.1"
  %"value.4" = load i64, i64* %"value.addr"
  %".32" = sext i32 10 to i64
  %".33" = srem i64 %"value.4", %".32"
  %".34" = sext i32 48 to i64
  %".35" = add i64 %".33", %".34"
  %".36" = trunc i64 %".35" to i8
  store i8 %".36", i8* %".31"
  %"value.5" = load i64, i64* %"value.addr"
  %".38" = sext i32 10 to i64
  %".39" = sdiv i64 %"value.5", %".38"
  store i64 %".39", i64* %"value.addr"
  %"pos.2" = load i64, i64* %"pos"
  %".41" = add i64 %"pos.2", 1
  store i64 %".41", i64* %"pos"
  br label %"while.cond"
while.end:
  %"write_pos" = alloca i64
  %".44" = sext i32 0 to i64
  store i64 %".44", i64* %"write_pos"
  %"remaining" = alloca i64
  %"pos.3" = load i64, i64* %"pos"
  store i64 %"pos.3", i64* %"remaining"
  br label %"while.cond.1"
while.cond.1:
  %"remaining.1" = load i64, i64* %"remaining"
  %".48" = sext i32 0 to i64
  %".49" = icmp ne i64 %"remaining.1", %".48"
  br i1 %".49", label %"while.body.1", label %"while.end.1"
while.body.1:
  %"remaining.2" = load i64, i64* %"remaining"
  %".51" = sub i64 %"remaining.2", 1
  store i64 %".51", i64* %"remaining"
  %"remaining.3" = load i64, i64* %"remaining"
  %"idx_trunc" = trunc i64 %"remaining.3" to i32
  %"array_gep" = getelementptr inbounds [32 x i8], [32 x i8]* %"temp", i32 0, i32 %"idx_trunc"
  %"array_load" = load i8, i8* %"array_gep"
  %"buffer.3" = load i8*, i8** %"buffer.addr"
  %"write_pos.1" = load i64, i64* %"write_pos"
  %".53" = getelementptr inbounds i8, i8* %"buffer.3", i64 %"write_pos.1"
  %"remaining.4" = load i64, i64* %"remaining"
  %"idx_trunc.1" = trunc i64 %"remaining.4" to i32
  %"array_gep.1" = getelementptr inbounds [32 x i8], [32 x i8]* %"temp", i32 0, i32 %"idx_trunc.1"
  %"array_load.1" = load i8, i8* %"array_gep.1"
  store i8 %"array_load.1", i8* %".53"
  %"write_pos.2" = load i64, i64* %"write_pos"
  %".55" = add i64 %"write_pos.2", 1
  store i64 %".55", i64* %"write_pos"
  br label %"while.cond.1"
while.end.1:
  %".58" = trunc i32 0 to i8
  %"buffer.4" = load i8*, i8** %"buffer.addr"
  %"write_pos.3" = load i64, i64* %"write_pos"
  %".59" = getelementptr inbounds i8, i8* %"buffer.4", i64 %"write_pos.3"
  %".60" = trunc i32 0 to i8
  store i8 %".60", i8* %".59"
  %"write_pos.4" = load i64, i64* %"write_pos"
  ret i64 %"write_pos.4"
}

define i32 @"str2i32__1__byte_ptr1__ret_int"(i8* %"str")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"result" = alloca i32
  store i32 0, i32* %"result"
  %"sign" = alloca i32
  store i32 1, i32* %"sign"
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"while.cond"
while.cond:
  %"str.1" = load i8*, i8** %"str.addr"
  %"i.1" = load i32, i32* %"i"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %"i.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".8" = zext i8 %"ptr_load" to i32
  %".9" = icmp eq i32 %".8", 32
  %"str.2" = load i8*, i8** %"str.addr"
  %"i.2" = load i32, i32* %"i"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.2", i32 %"i.2"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".10" = zext i8 %"ptr_load.1" to i32
  %".11" = icmp eq i32 %".10", 9
  %".12" = or i1 %".9", %".11"
  %"str.3" = load i8*, i8** %"str.addr"
  %"i.3" = load i32, i32* %"i"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"str.3", i32 %"i.3"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  %".13" = zext i8 %"ptr_load.2" to i32
  %".14" = icmp eq i32 %".13", 10
  %".15" = or i1 %".12", %".14"
  %"str.4" = load i8*, i8** %"str.addr"
  %"i.4" = load i32, i32* %"i"
  %"ptr_gep.3" = getelementptr inbounds i8, i8* %"str.4", i32 %"i.4"
  %"ptr_load.3" = load i8, i8* %"ptr_gep.3"
  %".16" = zext i8 %"ptr_load.3" to i32
  %".17" = icmp eq i32 %".16", 13
  %".18" = or i1 %".15", %".17"
  br i1 %".18", label %"while.body", label %"while.end"
while.body:
  %"i.5" = load i32, i32* %"i"
  %".20" = add i32 %"i.5", 1
  store i32 %".20", i32* %"i"
  br label %"while.cond"
while.end:
  %"str.5" = load i8*, i8** %"str.addr"
  %"i.6" = load i32, i32* %"i"
  %"ptr_gep.4" = getelementptr inbounds i8, i8* %"str.5", i32 %"i.6"
  %"ptr_load.4" = load i8, i8* %"ptr_gep.4"
  %".23" = zext i8 %"ptr_load.4" to i32
  %".24" = icmp eq i32 %".23", 45
  br i1 %".24", label %"then", label %"else"
then:
  %".26" = sub i32 0, 1
  store i32 %".26", i32* %"sign"
  %"i.7" = load i32, i32* %"i"
  %".28" = add i32 %"i.7", 1
  store i32 %".28", i32* %"i"
  br label %"ifcont"
else:
  %"str.6" = load i8*, i8** %"str.addr"
  %"i.8" = load i32, i32* %"i"
  %"ptr_gep.5" = getelementptr inbounds i8, i8* %"str.6", i32 %"i.8"
  %"ptr_load.5" = load i8, i8* %"ptr_gep.5"
  %".31" = zext i8 %"ptr_load.5" to i32
  %".32" = icmp eq i32 %".31", 43
  br i1 %".32", label %"elif_then_0", label %"elif_else_0"
ifcont:
  br label %"while.cond.1"
elif_then_0:
  %"i.9" = load i32, i32* %"i"
  %".34" = add i32 %"i.9", 1
  store i32 %".34", i32* %"i"
  br label %"ifcont"
elif_else_0:
  br label %"ifcont"
while.cond.1:
  %"str.7" = load i8*, i8** %"str.addr"
  %"i.10" = load i32, i32* %"i"
  %"ptr_gep.6" = getelementptr inbounds i8, i8* %"str.7", i32 %"i.10"
  %"ptr_load.6" = load i8, i8* %"ptr_gep.6"
  %".39" = zext i8 %"ptr_load.6" to i32
  %".40" = icmp ne i32 %".39", 0
  br i1 %".40", label %"while.body.1", label %"while.end.1"
while.body.1:
  %"c" = alloca i8
  %"str.8" = load i8*, i8** %"str.addr"
  %"i.11" = load i32, i32* %"i"
  %"ptr_gep.7" = getelementptr inbounds i8, i8* %"str.8", i32 %"i.11"
  %"ptr_load.7" = load i8, i8* %"ptr_gep.7"
  store i8 %"ptr_load.7", i8* %"c"
  %"c.1" = load i8, i8* %"c"
  %".43" = zext i8 %"c.1" to i32
  %".44" = icmp sge i32 %".43", 48
  %"c.2" = load i8, i8* %"c"
  %".45" = zext i8 %"c.2" to i32
  %".46" = icmp sle i32 %".45", 57
  %".47" = and i1 %".44", %".46"
  br i1 %".47", label %"then.1", label %"else.1"
while.end.1:
  %"result.2" = load i32, i32* %"result"
  %"sign.1" = load i32, i32* %"sign"
  %".60" = mul i32 %"result.2", %"sign.1"
  ret i32 %".60"
then.1:
  %"digit" = alloca i32
  %"c.3" = load i8, i8* %"c"
  %".49" = zext i8 %"c.3" to i32
  %".50" = sub i32 %".49", 48
  store i32 %".50", i32* %"digit"
  %"result.1" = load i32, i32* %"result"
  %".52" = mul i32 %"result.1", 10
  %"digit.1" = load i32, i32* %"digit"
  %".53" = add i32 %".52", %"digit.1"
  store i32 %".53", i32* %"result"
  br label %"ifcont.1"
else.1:
  br label %"while.end.1"
ifcont.1:
  %"i.12" = load i32, i32* %"i"
  %".57" = add i32 %"i.12", 1
  store i32 %".57", i32* %"i"
  br label %"while.cond.1"
}

define i32 @"str2u32__1__byte_ptr1__ret_uint"(i8* %"str")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"result" = alloca i32
  store i32 0, i32* %"result"
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"while.cond"
while.cond:
  %"str.1" = load i8*, i8** %"str.addr"
  %"i.1" = load i32, i32* %"i"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %"i.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".7" = trunc i32 32 to i8
  %".8" = icmp eq i8 %"ptr_load", %".7"
  %"str.2" = load i8*, i8** %"str.addr"
  %"i.2" = load i32, i32* %"i"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.2", i32 %"i.2"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".9" = trunc i32 9 to i8
  %".10" = icmp eq i8 %"ptr_load.1", %".9"
  %".11" = or i1 %".8", %".10"
  %"str.3" = load i8*, i8** %"str.addr"
  %"i.3" = load i32, i32* %"i"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"str.3", i32 %"i.3"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  %".12" = trunc i32 10 to i8
  %".13" = icmp eq i8 %"ptr_load.2", %".12"
  %".14" = or i1 %".11", %".13"
  %"str.4" = load i8*, i8** %"str.addr"
  %"i.4" = load i32, i32* %"i"
  %"ptr_gep.3" = getelementptr inbounds i8, i8* %"str.4", i32 %"i.4"
  %"ptr_load.3" = load i8, i8* %"ptr_gep.3"
  %".15" = trunc i32 13 to i8
  %".16" = icmp eq i8 %"ptr_load.3", %".15"
  %".17" = or i1 %".14", %".16"
  br i1 %".17", label %"while.body", label %"while.end"
while.body:
  %"i.5" = load i32, i32* %"i"
  %".19" = add i32 %"i.5", 1
  store i32 %".19", i32* %"i"
  br label %"while.cond"
while.end:
  %"str.5" = load i8*, i8** %"str.addr"
  %"i.6" = load i32, i32* %"i"
  %"ptr_gep.4" = getelementptr inbounds i8, i8* %"str.5", i32 %"i.6"
  %"ptr_load.4" = load i8, i8* %"ptr_gep.4"
  %".22" = trunc i32 45 to i8
  %".23" = icmp eq i8 %"ptr_load.4", %".22"
  br i1 %".23", label %"then", label %"else"
then:
  ret i32 0
else:
  %"str.6" = load i8*, i8** %"str.addr"
  %"i.7" = load i32, i32* %"i"
  %"ptr_gep.5" = getelementptr inbounds i8, i8* %"str.6", i32 %"i.7"
  %"ptr_load.5" = load i8, i8* %"ptr_gep.5"
  %".26" = trunc i32 43 to i8
  %".27" = icmp eq i8 %"ptr_load.5", %".26"
  br i1 %".27", label %"elif_then_0", label %"elif_else_0"
ifcont:
  br label %"while.cond.1"
elif_then_0:
  %"i.8" = load i32, i32* %"i"
  %".29" = add i32 %"i.8", 1
  store i32 %".29", i32* %"i"
  br label %"ifcont"
elif_else_0:
  br label %"ifcont"
while.cond.1:
  %"str.7" = load i8*, i8** %"str.addr"
  %"i.9" = load i32, i32* %"i"
  %"ptr_gep.6" = getelementptr inbounds i8, i8* %"str.7", i32 %"i.9"
  %"ptr_load.6" = load i8, i8* %"ptr_gep.6"
  %".34" = trunc i32 0 to i8
  %".35" = icmp ne i8 %"ptr_load.6", %".34"
  br i1 %".35", label %"while.body.1", label %"while.end.1"
while.body.1:
  %"c" = alloca i8
  %"str.8" = load i8*, i8** %"str.addr"
  %"i.10" = load i32, i32* %"i"
  %"ptr_gep.7" = getelementptr inbounds i8, i8* %"str.8", i32 %"i.10"
  %"ptr_load.7" = load i8, i8* %"ptr_gep.7"
  store i8 %"ptr_load.7", i8* %"c"
  %"c.1" = load i8, i8* %"c"
  %".38" = trunc i32 48 to i8
  %".39" = icmp sge i8 %"c.1", %".38"
  %"c.2" = load i8, i8* %"c"
  %".40" = trunc i32 57 to i8
  %".41" = icmp sle i8 %"c.2", %".40"
  %".42" = and i1 %".39", %".41"
  br i1 %".42", label %"then.1", label %"else.1"
while.end.1:
  %"result.2" = load i32, i32* %"result"
  ret i32 %"result.2"
then.1:
  %"digit" = alloca i32
  %"c.3" = load i8, i8* %"c"
  %".44" = trunc i32 48 to i8
  %".45" = sub i8 %"c.3", %".44"
  %".46" = zext i8 %".45" to i32
  store i32 %".46", i32* %"digit"
  %"result.1" = load i32, i32* %"result"
  %".48" = mul i32 %"result.1", 10
  %"digit.1" = load i32, i32* %"digit"
  %".49" = add i32 %".48", %"digit.1"
  store i32 %".49", i32* %"result"
  br label %"ifcont.1"
else.1:
  br label %"while.end.1"
ifcont.1:
  %"i.11" = load i32, i32* %"i"
  %".53" = add i32 %"i.11", 1
  store i32 %".53", i32* %"i"
  br label %"while.cond.1"
}

define i64 @"str2i64__1__byte_ptr1__ret_i64"(i8* %"str")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"result" = alloca i64
  %".4" = sext i32 0 to i64
  store i64 %".4", i64* %"result"
  %"sign" = alloca i64
  %".6" = sext i32 1 to i64
  store i64 %".6", i64* %"sign"
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"while.cond"
while.cond:
  %"str.1" = load i8*, i8** %"str.addr"
  %"i.1" = load i32, i32* %"i"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %"i.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".10" = trunc i32 32 to i8
  %".11" = icmp eq i8 %"ptr_load", %".10"
  %"str.2" = load i8*, i8** %"str.addr"
  %"i.2" = load i32, i32* %"i"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.2", i32 %"i.2"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".12" = trunc i32 9 to i8
  %".13" = icmp eq i8 %"ptr_load.1", %".12"
  %".14" = or i1 %".11", %".13"
  %"str.3" = load i8*, i8** %"str.addr"
  %"i.3" = load i32, i32* %"i"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"str.3", i32 %"i.3"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  %".15" = trunc i32 10 to i8
  %".16" = icmp eq i8 %"ptr_load.2", %".15"
  %".17" = or i1 %".14", %".16"
  %"str.4" = load i8*, i8** %"str.addr"
  %"i.4" = load i32, i32* %"i"
  %"ptr_gep.3" = getelementptr inbounds i8, i8* %"str.4", i32 %"i.4"
  %"ptr_load.3" = load i8, i8* %"ptr_gep.3"
  %".18" = trunc i32 13 to i8
  %".19" = icmp eq i8 %"ptr_load.3", %".18"
  %".20" = or i1 %".17", %".19"
  br i1 %".20", label %"while.body", label %"while.end"
while.body:
  %"i.5" = load i32, i32* %"i"
  %".22" = add i32 %"i.5", 1
  store i32 %".22", i32* %"i"
  br label %"while.cond"
while.end:
  %"str.5" = load i8*, i8** %"str.addr"
  %"i.6" = load i32, i32* %"i"
  %"ptr_gep.4" = getelementptr inbounds i8, i8* %"str.5", i32 %"i.6"
  %"ptr_load.4" = load i8, i8* %"ptr_gep.4"
  %".25" = trunc i32 45 to i8
  %".26" = icmp eq i8 %"ptr_load.4", %".25"
  br i1 %".26", label %"then", label %"else"
then:
  %".28" = sub i32 0, 1
  %".29" = sext i32 %".28" to i64
  store i64 %".29", i64* %"sign"
  %"i.7" = load i32, i32* %"i"
  %".31" = add i32 %"i.7", 1
  store i32 %".31", i32* %"i"
  br label %"ifcont"
else:
  %"str.6" = load i8*, i8** %"str.addr"
  %"i.8" = load i32, i32* %"i"
  %"ptr_gep.5" = getelementptr inbounds i8, i8* %"str.6", i32 %"i.8"
  %"ptr_load.5" = load i8, i8* %"ptr_gep.5"
  %".34" = trunc i32 43 to i8
  %".35" = icmp eq i8 %"ptr_load.5", %".34"
  br i1 %".35", label %"elif_then_0", label %"elif_else_0"
ifcont:
  br label %"while.cond.1"
elif_then_0:
  %"i.9" = load i32, i32* %"i"
  %".37" = add i32 %"i.9", 1
  store i32 %".37", i32* %"i"
  br label %"ifcont"
elif_else_0:
  br label %"ifcont"
while.cond.1:
  %"str.7" = load i8*, i8** %"str.addr"
  %"i.10" = load i32, i32* %"i"
  %"ptr_gep.6" = getelementptr inbounds i8, i8* %"str.7", i32 %"i.10"
  %"ptr_load.6" = load i8, i8* %"ptr_gep.6"
  %".42" = trunc i32 0 to i8
  %".43" = icmp ne i8 %"ptr_load.6", %".42"
  br i1 %".43", label %"while.body.1", label %"while.end.1"
while.body.1:
  %"c" = alloca i8
  %"str.8" = load i8*, i8** %"str.addr"
  %"i.11" = load i32, i32* %"i"
  %"ptr_gep.7" = getelementptr inbounds i8, i8* %"str.8", i32 %"i.11"
  %"ptr_load.7" = load i8, i8* %"ptr_gep.7"
  store i8 %"ptr_load.7", i8* %"c"
  %"c.1" = load i8, i8* %"c"
  %".46" = trunc i32 48 to i8
  %".47" = icmp sge i8 %"c.1", %".46"
  %"c.2" = load i8, i8* %"c"
  %".48" = trunc i32 57 to i8
  %".49" = icmp sle i8 %"c.2", %".48"
  %".50" = and i1 %".47", %".49"
  br i1 %".50", label %"then.1", label %"else.1"
while.end.1:
  %"result.2" = load i64, i64* %"result"
  %"sign.1" = load i64, i64* %"sign"
  %".65" = mul i64 %"result.2", %"sign.1"
  ret i64 %".65"
then.1:
  %"digit" = alloca i64
  %"c.3" = load i8, i8* %"c"
  %".52" = trunc i32 48 to i8
  %".53" = sub i8 %"c.3", %".52"
  %".54" = sext i8 %".53" to i64
  store i64 %".54", i64* %"digit"
  %"result.1" = load i64, i64* %"result"
  %".56" = sext i32 10 to i64
  %".57" = mul i64 %"result.1", %".56"
  %"digit.1" = load i64, i64* %"digit"
  %".58" = add i64 %".57", %"digit.1"
  store i64 %".58", i64* %"result"
  br label %"ifcont.1"
else.1:
  br label %"while.end.1"
ifcont.1:
  %"i.12" = load i32, i32* %"i"
  %".62" = add i32 %"i.12", 1
  store i32 %".62", i32* %"i"
  br label %"while.cond.1"
}

define i64 @"str2u64__1__byte_ptr1__ret_u64"(i8* %"str")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"result" = alloca i64
  %".4" = sext i32 0 to i64
  store i64 %".4", i64* %"result"
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"while.cond"
while.cond:
  %"str.1" = load i8*, i8** %"str.addr"
  %"i.1" = load i32, i32* %"i"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %"i.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".8" = trunc i32 32 to i8
  %".9" = icmp eq i8 %"ptr_load", %".8"
  %"str.2" = load i8*, i8** %"str.addr"
  %"i.2" = load i32, i32* %"i"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.2", i32 %"i.2"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".10" = trunc i32 9 to i8
  %".11" = icmp eq i8 %"ptr_load.1", %".10"
  %".12" = or i1 %".9", %".11"
  %"str.3" = load i8*, i8** %"str.addr"
  %"i.3" = load i32, i32* %"i"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"str.3", i32 %"i.3"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  %".13" = trunc i32 10 to i8
  %".14" = icmp eq i8 %"ptr_load.2", %".13"
  %".15" = or i1 %".12", %".14"
  %"str.4" = load i8*, i8** %"str.addr"
  %"i.4" = load i32, i32* %"i"
  %"ptr_gep.3" = getelementptr inbounds i8, i8* %"str.4", i32 %"i.4"
  %"ptr_load.3" = load i8, i8* %"ptr_gep.3"
  %".16" = trunc i32 13 to i8
  %".17" = icmp eq i8 %"ptr_load.3", %".16"
  %".18" = or i1 %".15", %".17"
  br i1 %".18", label %"while.body", label %"while.end"
while.body:
  %"i.5" = load i32, i32* %"i"
  %".20" = add i32 %"i.5", 1
  store i32 %".20", i32* %"i"
  br label %"while.cond"
while.end:
  %"str.5" = load i8*, i8** %"str.addr"
  %"i.6" = load i32, i32* %"i"
  %"ptr_gep.4" = getelementptr inbounds i8, i8* %"str.5", i32 %"i.6"
  %"ptr_load.4" = load i8, i8* %"ptr_gep.4"
  %".23" = trunc i32 45 to i8
  %".24" = icmp eq i8 %"ptr_load.4", %".23"
  br i1 %".24", label %"then", label %"else"
then:
  %".26" = sext i32 0 to i64
  ret i64 %".26"
else:
  %"str.6" = load i8*, i8** %"str.addr"
  %"i.7" = load i32, i32* %"i"
  %"ptr_gep.5" = getelementptr inbounds i8, i8* %"str.6", i32 %"i.7"
  %"ptr_load.5" = load i8, i8* %"ptr_gep.5"
  %".28" = trunc i32 43 to i8
  %".29" = icmp eq i8 %"ptr_load.5", %".28"
  br i1 %".29", label %"elif_then_0", label %"elif_else_0"
ifcont:
  br label %"while.cond.1"
elif_then_0:
  %"i.8" = load i32, i32* %"i"
  %".31" = add i32 %"i.8", 1
  store i32 %".31", i32* %"i"
  br label %"ifcont"
elif_else_0:
  br label %"ifcont"
while.cond.1:
  %"str.7" = load i8*, i8** %"str.addr"
  %"i.9" = load i32, i32* %"i"
  %"ptr_gep.6" = getelementptr inbounds i8, i8* %"str.7", i32 %"i.9"
  %"ptr_load.6" = load i8, i8* %"ptr_gep.6"
  %".36" = trunc i32 0 to i8
  %".37" = icmp ne i8 %"ptr_load.6", %".36"
  br i1 %".37", label %"while.body.1", label %"while.end.1"
while.body.1:
  %"c" = alloca i8
  %"str.8" = load i8*, i8** %"str.addr"
  %"i.10" = load i32, i32* %"i"
  %"ptr_gep.7" = getelementptr inbounds i8, i8* %"str.8", i32 %"i.10"
  %"ptr_load.7" = load i8, i8* %"ptr_gep.7"
  store i8 %"ptr_load.7", i8* %"c"
  %"c.1" = load i8, i8* %"c"
  %".40" = trunc i32 48 to i8
  %".41" = icmp sge i8 %"c.1", %".40"
  %"c.2" = load i8, i8* %"c"
  %".42" = trunc i32 57 to i8
  %".43" = icmp sle i8 %"c.2", %".42"
  %".44" = and i1 %".41", %".43"
  br i1 %".44", label %"then.1", label %"else.1"
while.end.1:
  %"result.2" = load i64, i64* %"result"
  ret i64 %"result.2"
then.1:
  %"digit" = alloca i64
  %"c.3" = load i8, i8* %"c"
  %".46" = trunc i32 48 to i8
  %".47" = sub i8 %"c.3", %".46"
  %".48" = zext i8 %".47" to i64
  store i64 %".48", i64* %"digit"
  %"result.1" = load i64, i64* %"result"
  %".50" = sext i32 10 to i64
  %".51" = mul i64 %"result.1", %".50"
  %"digit.1" = load i64, i64* %"digit"
  %".52" = add i64 %".51", %"digit.1"
  store i64 %".52", i64* %"result"
  br label %"ifcont.1"
else.1:
  br label %"while.end.1"
ifcont.1:
  %"i.11" = load i32, i32* %"i"
  %".56" = add i32 %"i.11", 1
  store i32 %".56", i32* %"i"
  br label %"while.cond.1"
}

define i32 @"float2str__3__float__byte_ptr1__i32__ret_i32"(float %"value", i8* %"buffer", i32 %"precision")
{
entry:
  %"value.addr" = alloca float
  store float %"value", float* %"value.addr"
  %"buffer.addr" = alloca i8*
  store i8* %"buffer", i8** %"buffer.addr"
  %"precision.addr" = alloca i32
  store i32 %"precision", i32* %"precision.addr"
  %"write_pos" = alloca i32
  store i32 0, i32* %"write_pos"
  %"value.1" = load float, float* %"value.addr"
  %".9" = fcmp olt float %"value.1",              0x0
  br i1 %".9", label %"then", label %"else"
then:
  %".11" = trunc i32 45 to i8
  %"buffer.1" = load i8*, i8** %"buffer.addr"
  %".12" = getelementptr inbounds i8, i8* %"buffer.1", i32 0
  %".13" = trunc i32 45 to i8
  store i8 %".13", i8* %".12"
  store i32 1, i32* %"write_pos"
  %"value.2" = load float, float* %"value.addr"
  %".16" = fsub float              0x0, %"value.2"
  store float %".16", float* %"value.addr"
  br label %"ifcont"
else:
  br label %"ifcont"
ifcont:
  %"value.3" = load float, float* %"value.addr"
  %".20" = fcmp oeq float %"value.3",              0x0
  br i1 %".20", label %"then.1", label %"else.1"
then.1:
  %".22" = trunc i32 48 to i8
  %"buffer.2" = load i8*, i8** %"buffer.addr"
  %"write_pos.1" = load i32, i32* %"write_pos"
  %".23" = getelementptr inbounds i8, i8* %"buffer.2", i32 %"write_pos.1"
  %".24" = trunc i32 48 to i8
  store i8 %".24", i8* %".23"
  %".26" = trunc i32 46 to i8
  %"buffer.3" = load i8*, i8** %"buffer.addr"
  %"write_pos.2" = load i32, i32* %"write_pos"
  %".27" = add i32 %"write_pos.2", 1
  %".28" = getelementptr inbounds i8, i8* %"buffer.3", i32 %".27"
  %".29" = trunc i32 46 to i8
  store i8 %".29", i8* %".28"
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"while.cond"
else.1:
  br label %"ifcont.1"
ifcont.1:
  %"int_part" = alloca i32
  %"value.4" = load float, float* %"value.addr"
  %".54" = fptosi float %"value.4" to i32
  store i32 %".54", i32* %"int_part"
  %"fractional" = alloca float
  %"value.5" = load float, float* %"value.addr"
  %"int_part.1" = load i32, i32* %"int_part"
  %".56" = sitofp i32 %"int_part.1" to float
  %".57" = fsub float %"value.5", %".56"
  store float %".57", float* %"fractional"
  %"frac_multiplier" = alloca i32
  store i32 1, i32* %"frac_multiplier"
  %"j" = alloca i32
  store i32 0, i32* %"j"
  br label %"while.cond.1"
while.cond:
  %"i.1" = load i32, i32* %"i"
  %"precision.1" = load i32, i32* %"precision.addr"
  %".33" = icmp slt i32 %"i.1", %"precision.1"
  br i1 %".33", label %"while.body", label %"while.end"
while.body:
  %".35" = trunc i32 48 to i8
  %"buffer.4" = load i8*, i8** %"buffer.addr"
  %"write_pos.3" = load i32, i32* %"write_pos"
  %".36" = add i32 %"write_pos.3", 2
  %"i.2" = load i32, i32* %"i"
  %".37" = add i32 %".36", %"i.2"
  %".38" = getelementptr inbounds i8, i8* %"buffer.4", i32 %".37"
  %".39" = trunc i32 48 to i8
  store i8 %".39", i8* %".38"
  %"i.3" = load i32, i32* %"i"
  %".41" = add i32 %"i.3", 1
  store i32 %".41", i32* %"i"
  br label %"while.cond"
while.end:
  %".44" = trunc i32 0 to i8
  %"buffer.5" = load i8*, i8** %"buffer.addr"
  %"write_pos.4" = load i32, i32* %"write_pos"
  %".45" = add i32 %"write_pos.4", 2
  %"precision.2" = load i32, i32* %"precision.addr"
  %".46" = add i32 %".45", %"precision.2"
  %".47" = getelementptr inbounds i8, i8* %"buffer.5", i32 %".46"
  %".48" = trunc i32 0 to i8
  store i8 %".48", i8* %".47"
  %"write_pos.5" = load i32, i32* %"write_pos"
  %".50" = add i32 %"write_pos.5", 1
  %"precision.3" = load i32, i32* %"precision.addr"
  %".51" = add i32 %".50", %"precision.3"
  ret i32 %".51"
while.cond.1:
  %"j.1" = load i32, i32* %"j"
  %"precision.4" = load i32, i32* %"precision.addr"
  %".62" = icmp slt i32 %"j.1", %"precision.4"
  br i1 %".62", label %"while.body.1", label %"while.end.1"
while.body.1:
  %"frac_multiplier.1" = load i32, i32* %"frac_multiplier"
  %".64" = mul i32 %"frac_multiplier.1", 10
  store i32 %".64", i32* %"frac_multiplier"
  %"j.2" = load i32, i32* %"j"
  %".66" = add i32 %"j.2", 1
  store i32 %".66", i32* %"j"
  br label %"while.cond.1"
while.end.1:
  %"scaled_frac" = alloca float
  %"fractional.1" = load float, float* %"fractional"
  %"frac_multiplier.2" = load i32, i32* %"frac_multiplier"
  %".69" = sitofp i32 %"frac_multiplier.2" to float
  %".70" = fmul float %"fractional.1", %".69"
  store float %".70", float* %"scaled_frac"
  %"frac_part" = alloca i32
  %"scaled_frac.1" = load float, float* %"scaled_frac"
  %".72" = fadd float %"scaled_frac.1", 0x3fe0000000000000
  %".73" = fptosi float %".72" to i32
  store i32 %".73", i32* %"frac_part"
  %"frac_part.1" = load i32, i32* %"frac_part"
  %"frac_multiplier.3" = load i32, i32* %"frac_multiplier"
  %".75" = icmp sge i32 %"frac_part.1", %"frac_multiplier.3"
  br i1 %".75", label %"then.2", label %"else.2"
then.2:
  %"int_part.2" = load i32, i32* %"int_part"
  %".77" = add i32 %"int_part.2", 1
  store i32 %".77", i32* %"int_part"
  store i32 0, i32* %"frac_part"
  %"int_part.3" = load i32, i32* %"int_part"
  %".80" = srem i32 %"int_part.3", 10
  %".81" = icmp eq i32 %".80", 0
  %"precision.5" = load i32, i32* %"precision.addr"
  %".82" = icmp sgt i32 %"precision.5", 0
  %".83" = and i1 %".81", %".82"
  br i1 %".83", label %"then.3", label %"else.3"
else.2:
  br label %"ifcont.2"
ifcont.2:
  %"int_part.4" = load i32, i32* %"int_part"
  %".89" = icmp eq i32 %"int_part.4", 0
  br i1 %".89", label %"then.4", label %"else.4"
then.3:
  br label %"ifcont.3"
else.3:
  br label %"ifcont.3"
ifcont.3:
  br label %"ifcont.2"
then.4:
  %".91" = trunc i32 48 to i8
  %"buffer.6" = load i8*, i8** %"buffer.addr"
  %"write_pos.6" = load i32, i32* %"write_pos"
  %".92" = getelementptr inbounds i8, i8* %"buffer.6", i32 %"write_pos.6"
  %".93" = trunc i32 48 to i8
  store i8 %".93", i8* %".92"
  %"write_pos.7" = load i32, i32* %"write_pos"
  %".95" = add i32 %"write_pos.7", 1
  store i32 %".95", i32* %"write_pos"
  br label %"ifcont.4"
else.4:
  %"int_temp" = alloca [32 x i8]
  %"temp_pos" = alloca i32
  store i32 0, i32* %"temp_pos"
  %"temp_int" = alloca i32
  %"int_part.5" = load i32, i32* %"int_part"
  store i32 %"int_part.5", i32* %"temp_int"
  br label %"while.cond.2"
ifcont.4:
  %"precision.6" = load i32, i32* %"precision.addr"
  %".129" = icmp sgt i32 %"precision.6", 0
  br i1 %".129", label %"then.5", label %"else.5"
while.cond.2:
  %"temp_int.1" = load i32, i32* %"temp_int"
  %".101" = icmp sgt i32 %"temp_int.1", 0
  br i1 %".101", label %"while.body.2", label %"while.end.2"
while.body.2:
  %"temp_int.2" = load i32, i32* %"temp_int"
  %".103" = srem i32 %"temp_int.2", 10
  %".104" = add i32 %".103", 48
  %".105" = trunc i32 %".104" to i8
  %"temp_pos.1" = load i32, i32* %"temp_pos"
  %".106" = getelementptr inbounds [32 x i8], [32 x i8]* %"int_temp", i1 0, i32 %"temp_pos.1"
  %"temp_int.3" = load i32, i32* %"temp_int"
  %".107" = srem i32 %"temp_int.3", 10
  %".108" = add i32 %".107", 48
  %".109" = trunc i32 %".108" to i8
  store i8 %".109", i8* %".106"
  %"temp_int.4" = load i32, i32* %"temp_int"
  %".111" = sdiv i32 %"temp_int.4", 10
  store i32 %".111", i32* %"temp_int"
  %"temp_pos.2" = load i32, i32* %"temp_pos"
  %".113" = add i32 %"temp_pos.2", 1
  store i32 %".113", i32* %"temp_pos"
  br label %"while.cond.2"
while.end.2:
  %"k" = alloca i32
  %"temp_pos.3" = load i32, i32* %"temp_pos"
  %".116" = sub i32 %"temp_pos.3", 1
  store i32 %".116", i32* %"k"
  br label %"while.cond.3"
while.cond.3:
  %"k.1" = load i32, i32* %"k"
  %".119" = icmp sge i32 %"k.1", 0
  br i1 %".119", label %"while.body.3", label %"while.end.3"
while.body.3:
  %"k.2" = load i32, i32* %"k"
  %"array_gep" = getelementptr inbounds [32 x i8], [32 x i8]* %"int_temp", i32 0, i32 %"k.2"
  %"array_load" = load i8, i8* %"array_gep"
  %"buffer.7" = load i8*, i8** %"buffer.addr"
  %"write_pos.8" = load i32, i32* %"write_pos"
  %".121" = getelementptr inbounds i8, i8* %"buffer.7", i32 %"write_pos.8"
  %"k.3" = load i32, i32* %"k"
  %"array_gep.1" = getelementptr inbounds [32 x i8], [32 x i8]* %"int_temp", i32 0, i32 %"k.3"
  %"array_load.1" = load i8, i8* %"array_gep.1"
  store i8 %"array_load.1", i8* %".121"
  %"write_pos.9" = load i32, i32* %"write_pos"
  %".123" = add i32 %"write_pos.9", 1
  store i32 %".123", i32* %"write_pos"
  %"k.4" = load i32, i32* %"k"
  %".125" = sub i32 %"k.4", 1
  store i32 %".125", i32* %"k"
  br label %"while.cond.3"
while.end.3:
  br label %"ifcont.4"
then.5:
  %".131" = trunc i32 46 to i8
  %"buffer.8" = load i8*, i8** %"buffer.addr"
  %"write_pos.10" = load i32, i32* %"write_pos"
  %".132" = getelementptr inbounds i8, i8* %"buffer.8", i32 %"write_pos.10"
  %".133" = trunc i32 46 to i8
  store i8 %".133", i8* %".132"
  %"write_pos.11" = load i32, i32* %"write_pos"
  %".135" = add i32 %"write_pos.11", 1
  store i32 %".135", i32* %"write_pos"
  %"frac_part.2" = load i32, i32* %"frac_part"
  %".137" = icmp eq i32 %"frac_part.2", 0
  br i1 %".137", label %"then.6", label %"else.6"
else.5:
  br label %"ifcont.5"
ifcont.5:
  %".201" = trunc i32 0 to i8
  %"buffer.12" = load i8*, i8** %"buffer.addr"
  %"write_pos.18" = load i32, i32* %"write_pos"
  %".202" = getelementptr inbounds i8, i8* %"buffer.12", i32 %"write_pos.18"
  %".203" = trunc i32 0 to i8
  store i8 %".203", i8* %".202"
  %"write_pos.19" = load i32, i32* %"write_pos"
  ret i32 %"write_pos.19"
then.6:
  %"m" = alloca i32
  store i32 0, i32* %"m"
  br label %"while.cond.4"
else.6:
  %"frac_temp" = alloca [32 x i8]
  %"frac_digits" = alloca i32
  store i32 0, i32* %"frac_digits"
  %"temp_frac" = alloca i32
  %"frac_part.3" = load i32, i32* %"frac_part"
  store i32 %"frac_part.3", i32* %"temp_frac"
  br label %"while.cond.5"
ifcont.6:
  br label %"ifcont.5"
while.cond.4:
  %"m.1" = load i32, i32* %"m"
  %"precision.7" = load i32, i32* %"precision.addr"
  %".141" = icmp slt i32 %"m.1", %"precision.7"
  br i1 %".141", label %"while.body.4", label %"while.end.4"
while.body.4:
  %".143" = trunc i32 48 to i8
  %"buffer.9" = load i8*, i8** %"buffer.addr"
  %"write_pos.12" = load i32, i32* %"write_pos"
  %".144" = getelementptr inbounds i8, i8* %"buffer.9", i32 %"write_pos.12"
  %".145" = trunc i32 48 to i8
  store i8 %".145", i8* %".144"
  %"write_pos.13" = load i32, i32* %"write_pos"
  %".147" = add i32 %"write_pos.13", 1
  store i32 %".147", i32* %"write_pos"
  %"m.2" = load i32, i32* %"m"
  %".149" = add i32 %"m.2", 1
  store i32 %".149", i32* %"m"
  br label %"while.cond.4"
while.end.4:
  br label %"ifcont.6"
while.cond.5:
  %"temp_frac.1" = load i32, i32* %"temp_frac"
  %".156" = icmp sgt i32 %"temp_frac.1", 0
  br i1 %".156", label %"while.body.5", label %"while.end.5"
while.body.5:
  %"temp_frac.2" = load i32, i32* %"temp_frac"
  %".158" = srem i32 %"temp_frac.2", 10
  %".159" = add i32 %".158", 48
  %".160" = trunc i32 %".159" to i8
  %"frac_digits.1" = load i32, i32* %"frac_digits"
  %".161" = getelementptr inbounds [32 x i8], [32 x i8]* %"frac_temp", i1 0, i32 %"frac_digits.1"
  %"temp_frac.3" = load i32, i32* %"temp_frac"
  %".162" = srem i32 %"temp_frac.3", 10
  %".163" = add i32 %".162", 48
  %".164" = trunc i32 %".163" to i8
  store i8 %".164", i8* %".161"
  %"temp_frac.4" = load i32, i32* %"temp_frac"
  %".166" = sdiv i32 %"temp_frac.4", 10
  store i32 %".166", i32* %"temp_frac"
  %"frac_digits.2" = load i32, i32* %"frac_digits"
  %".168" = add i32 %"frac_digits.2", 1
  store i32 %".168", i32* %"frac_digits"
  br label %"while.cond.5"
while.end.5:
  %"leading_zeros" = alloca i32
  %"precision.8" = load i32, i32* %"precision.addr"
  %"frac_digits.3" = load i32, i32* %"frac_digits"
  %".171" = sub i32 %"precision.8", %"frac_digits.3"
  store i32 %".171", i32* %"leading_zeros"
  %"n" = alloca i32
  store i32 0, i32* %"n"
  br label %"while.cond.6"
while.cond.6:
  %"n.1" = load i32, i32* %"n"
  %"leading_zeros.1" = load i32, i32* %"leading_zeros"
  %".175" = icmp slt i32 %"n.1", %"leading_zeros.1"
  br i1 %".175", label %"while.body.6", label %"while.end.6"
while.body.6:
  %".177" = trunc i32 48 to i8
  %"buffer.10" = load i8*, i8** %"buffer.addr"
  %"write_pos.14" = load i32, i32* %"write_pos"
  %".178" = getelementptr inbounds i8, i8* %"buffer.10", i32 %"write_pos.14"
  %".179" = trunc i32 48 to i8
  store i8 %".179", i8* %".178"
  %"write_pos.15" = load i32, i32* %"write_pos"
  %".181" = add i32 %"write_pos.15", 1
  store i32 %".181", i32* %"write_pos"
  %"n.2" = load i32, i32* %"n"
  %".183" = add i32 %"n.2", 1
  store i32 %".183", i32* %"n"
  br label %"while.cond.6"
while.end.6:
  %"p" = alloca i32
  %"frac_digits.4" = load i32, i32* %"frac_digits"
  %".186" = sub i32 %"frac_digits.4", 1
  store i32 %".186", i32* %"p"
  br label %"while.cond.7"
while.cond.7:
  %"p.1" = load i32, i32* %"p"
  %".189" = icmp sge i32 %"p.1", 0
  br i1 %".189", label %"while.body.7", label %"while.end.7"
while.body.7:
  %"p.2" = load i32, i32* %"p"
  %"array_gep.2" = getelementptr inbounds [32 x i8], [32 x i8]* %"frac_temp", i32 0, i32 %"p.2"
  %"array_load.2" = load i8, i8* %"array_gep.2"
  %"buffer.11" = load i8*, i8** %"buffer.addr"
  %"write_pos.16" = load i32, i32* %"write_pos"
  %".191" = getelementptr inbounds i8, i8* %"buffer.11", i32 %"write_pos.16"
  %"p.3" = load i32, i32* %"p"
  %"array_gep.3" = getelementptr inbounds [32 x i8], [32 x i8]* %"frac_temp", i32 0, i32 %"p.3"
  %"array_load.3" = load i8, i8* %"array_gep.3"
  store i8 %"array_load.3", i8* %".191"
  %"write_pos.17" = load i32, i32* %"write_pos"
  %".193" = add i32 %"write_pos.17", 1
  store i32 %".193", i32* %"write_pos"
  %"p.4" = load i32, i32* %"p"
  %".195" = sub i32 %"p.4", 1
  store i32 %".195", i32* %"p"
  br label %"while.cond.7"
while.end.7:
  br label %"ifcont.6"
}

define i1 @"is_whitespace__1__char__ret_bool"(i8 %"c")
{
entry:
  %"c.addr" = alloca i8
  store i8 %"c", i8* %"c.addr"
  %"c.1" = load i8, i8* %"c.addr"
  %".4" = icmp eq i8 %"c.1", 32
  %"c.2" = load i8, i8* %"c.addr"
  %".5" = icmp eq i8 %"c.2", 9
  %".6" = or i1 %".4", %".5"
  %"c.3" = load i8, i8* %"c.addr"
  %".7" = icmp eq i8 %"c.3", 10
  %".8" = or i1 %".6", %".7"
  %"c.4" = load i8, i8* %"c.addr"
  %".9" = icmp eq i8 %"c.4", 13
  %".10" = or i1 %".8", %".9"
  ret i1 %".10"
}

define i1 @"is_digit__1__char__ret_bool"(i8 %"c")
{
entry:
  %"c.addr" = alloca i8
  store i8 %"c", i8* %"c.addr"
  %"c.1" = load i8, i8* %"c.addr"
  %".4" = icmp sge i8 %"c.1", 48
  %"c.2" = load i8, i8* %"c.addr"
  %".5" = icmp sle i8 %"c.2", 57
  %".6" = and i1 %".4", %".5"
  ret i1 %".6"
}

define i1 @"is_alpha__1__char__ret_bool"(i8 %"c")
{
entry:
  %"c.addr" = alloca i8
  store i8 %"c", i8* %"c.addr"
  %"c.1" = load i8, i8* %"c.addr"
  %".4" = icmp sge i8 %"c.1", 97
  %"c.2" = load i8, i8* %"c.addr"
  %".5" = icmp sle i8 %"c.2", 122
  %".6" = and i1 %".4", %".5"
  %"c.3" = load i8, i8* %"c.addr"
  %".7" = icmp sge i8 %"c.3", 65
  %"c.4" = load i8, i8* %"c.addr"
  %".8" = icmp sle i8 %"c.4", 90
  %".9" = and i1 %".7", %".8"
  %".10" = or i1 %".6", %".9"
  ret i1 %".10"
}

define i1 @"is_alnum__1__char__ret_bool"(i8 %"c")
{
entry:
  %"c.addr" = alloca i8
  store i8 %"c", i8* %"c.addr"
  %"c.1" = load i8, i8* %"c.addr"
  %".4" = call i1 @"is_alpha__1__char__ret_bool"(i8 %"c.1")
  %"c.2" = load i8, i8* %"c.addr"
  %".5" = call i1 @"is_digit__1__char__ret_bool"(i8 %"c.2")
  %".6" = or i1 %".4", %".5"
  ret i1 %".6"
}

define i1 @"is_hex_digit__1__char__ret_bool"(i8 %"c")
{
entry:
  %"c.addr" = alloca i8
  store i8 %"c", i8* %"c.addr"
  %"c.1" = load i8, i8* %"c.addr"
  %".4" = call i1 @"is_digit__1__char__ret_bool"(i8 %"c.1")
  %"c.2" = load i8, i8* %"c.addr"
  %".5" = icmp sge i8 %"c.2", 97
  %"c.3" = load i8, i8* %"c.addr"
  %".6" = icmp sle i8 %"c.3", 102
  %".7" = and i1 %".5", %".6"
  %".8" = or i1 %".4", %".7"
  %"c.4" = load i8, i8* %"c.addr"
  %".9" = icmp sge i8 %"c.4", 65
  %"c.5" = load i8, i8* %"c.addr"
  %".10" = icmp sle i8 %"c.5", 70
  %".11" = and i1 %".9", %".10"
  %".12" = or i1 %".8", %".11"
  ret i1 %".12"
}

define i1 @"is_identifier_start__1__char__ret_bool"(i8 %"c")
{
entry:
  %"c.addr" = alloca i8
  store i8 %"c", i8* %"c.addr"
  %"c.1" = load i8, i8* %"c.addr"
  %".4" = call i1 @"is_alpha__1__char__ret_bool"(i8 %"c.1")
  %"c.2" = load i8, i8* %"c.addr"
  %".5" = icmp eq i8 %"c.2", 95
  %".6" = or i1 %".4", %".5"
  ret i1 %".6"
}

define i1 @"is_identifier_char__1__char__ret_bool"(i8 %"c")
{
entry:
  %"c.addr" = alloca i8
  store i8 %"c", i8* %"c.addr"
  %"c.1" = load i8, i8* %"c.addr"
  %".4" = call i1 @"is_alnum__1__char__ret_bool"(i8 %"c.1")
  %"c.2" = load i8, i8* %"c.addr"
  %".5" = icmp eq i8 %"c.2", 95
  %".6" = or i1 %".4", %".5"
  ret i1 %".6"
}

define i1 @"is_newline__1__char__ret_bool"(i8 %"c")
{
entry:
  %"c.addr" = alloca i8
  store i8 %"c", i8* %"c.addr"
  %"c.1" = load i8, i8* %"c.addr"
  %".4" = icmp eq i8 %"c.1", 10
  %"c.2" = load i8, i8* %"c.addr"
  %".5" = icmp eq i8 %"c.2", 13
  %".6" = or i1 %".4", %".5"
  ret i1 %".6"
}

define i8 @"to_lower__1__char__ret_char"(i8 %"c")
{
entry:
  %"c.addr" = alloca i8
  store i8 %"c", i8* %"c.addr"
  %"c.1" = load i8, i8* %"c.addr"
  %".4" = icmp sge i8 %"c.1", 65
  %"c.2" = load i8, i8* %"c.addr"
  %".5" = icmp sle i8 %"c.2", 90
  %".6" = and i1 %".4", %".5"
  br i1 %".6", label %"then", label %"else"
then:
  %"c.3" = load i8, i8* %"c.addr"
  %".8" = zext i8 %"c.3" to i32
  %".9" = add i32 %".8", 32
  %".10" = trunc i32 %".9" to i8
  ret i8 %".10"
else:
  br label %"ifcont"
ifcont:
  %"c.4" = load i8, i8* %"c.addr"
  ret i8 %"c.4"
}

define i8 @"to_upper__1__char__ret_char"(i8 %"c")
{
entry:
  %"c.addr" = alloca i8
  store i8 %"c", i8* %"c.addr"
  %"c.1" = load i8, i8* %"c.addr"
  %".4" = icmp sge i8 %"c.1", 97
  %"c.2" = load i8, i8* %"c.addr"
  %".5" = icmp sle i8 %"c.2", 122
  %".6" = and i1 %".4", %".5"
  br i1 %".6", label %"then", label %"else"
then:
  %"c.3" = load i8, i8* %"c.addr"
  %".8" = zext i8 %"c.3" to i32
  %".9" = sub i32 %".8", 32
  %".10" = trunc i32 %".9" to i8
  ret i8 %".10"
else:
  br label %"ifcont"
ifcont:
  %"c.4" = load i8, i8* %"c.addr"
  ret i8 %"c.4"
}

define i32 @"char_to_digit__1__char__ret_int"(i8 %"c")
{
entry:
  %"c.addr" = alloca i8
  store i8 %"c", i8* %"c.addr"
  %"c.1" = load i8, i8* %"c.addr"
  %".4" = icmp sge i8 %"c.1", 48
  %"c.2" = load i8, i8* %"c.addr"
  %".5" = icmp sle i8 %"c.2", 57
  %".6" = and i1 %".4", %".5"
  br i1 %".6", label %"then", label %"else"
then:
  %"c.3" = load i8, i8* %"c.addr"
  %".8" = sub i8 %"c.3", 48
  %".9" = sext i8 %".8" to i32
  ret i32 %".9"
else:
  br label %"ifcont"
ifcont:
  %".12" = sub i32 0, 1
  ret i32 %".12"
}

define i32 @"hex_to_int__1__char__ret_int"(i8 %"c")
{
entry:
  %"c.addr" = alloca i8
  store i8 %"c", i8* %"c.addr"
  %"c.1" = load i8, i8* %"c.addr"
  %".4" = icmp sge i8 %"c.1", 48
  %"c.2" = load i8, i8* %"c.addr"
  %".5" = icmp sle i8 %"c.2", 57
  %".6" = and i1 %".4", %".5"
  br i1 %".6", label %"then", label %"else"
then:
  %"c.3" = load i8, i8* %"c.addr"
  %".8" = sub i8 %"c.3", 48
  %".9" = sext i8 %".8" to i32
  ret i32 %".9"
else:
  br label %"ifcont"
ifcont:
  %"c.4" = load i8, i8* %"c.addr"
  %".12" = icmp sge i8 %"c.4", 97
  %"c.5" = load i8, i8* %"c.addr"
  %".13" = icmp sle i8 %"c.5", 102
  %".14" = and i1 %".12", %".13"
  br i1 %".14", label %"then.1", label %"else.1"
then.1:
  %"c.6" = load i8, i8* %"c.addr"
  %".16" = sub i8 %"c.6", 97
  %".17" = zext i8 %".16" to i32
  %".18" = add i32 10, %".17"
  ret i32 %".18"
else.1:
  br label %"ifcont.1"
ifcont.1:
  %"c.7" = load i8, i8* %"c.addr"
  %".21" = icmp sge i8 %"c.7", 65
  %"c.8" = load i8, i8* %"c.addr"
  %".22" = icmp sle i8 %"c.8", 70
  %".23" = and i1 %".21", %".22"
  br i1 %".23", label %"then.2", label %"else.2"
then.2:
  %"c.9" = load i8, i8* %"c.addr"
  %".25" = sub i8 %"c.9", 65
  %".26" = zext i8 %".25" to i32
  %".27" = add i32 10, %".26"
  ret i32 %".27"
else.2:
  br label %"ifcont.2"
ifcont.2:
  %".30" = sub i32 0, 1
  ret i32 %".30"
}

define i32 @"find_char__3__byte_ptr1__char__int__ret_int"(i8* %"str", i8 %"ch", i32 %"start_pos")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"ch.addr" = alloca i8
  store i8 %"ch", i8* %"ch.addr"
  %"start_pos.addr" = alloca i32
  store i32 %"start_pos", i32* %"start_pos.addr"
  %"i" = alloca i32
  %"start_pos.1" = load i32, i32* %"start_pos.addr"
  store i32 %"start_pos.1", i32* %"i"
  br label %"for.cond"
for.cond:
  %"str.1" = load i8*, i8** %"str.addr"
  %"i.1" = load i32, i32* %"i"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %"i.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".10" = zext i8 %"ptr_load" to i32
  %".11" = icmp ne i32 %".10", 0
  br i1 %".11", label %"for.body", label %"for.end"
for.body:
  %"str.2" = load i8*, i8** %"str.addr"
  %"i.2" = load i32, i32* %"i"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.2", i32 %"i.2"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %"ch.1" = load i8, i8* %"ch.addr"
  %".13" = icmp eq i8 %"ptr_load.1", %"ch.1"
  br i1 %".13", label %"then", label %"else"
for.update:
  %"i.4" = load i32, i32* %"i"
  %".18" = add i32 %"i.4", 1
  store i32 %".18", i32* %"i"
  br label %"for.cond"
for.end:
  %".21" = sub i32 0, 1
  ret i32 %".21"
then:
  %"i.3" = load i32, i32* %"i"
  ret i32 %"i.3"
else:
  br label %"ifcont"
ifcont:
  br label %"for.update"
}

define i32 @"find_char_last__2__byte_ptr1__char__ret_int"(i8* %"str", i8 %"ch")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"ch.addr" = alloca i8
  store i8 %"ch", i8* %"ch.addr"
  %"last" = alloca i32
  %".6" = sub i32 0, 1
  store i32 %".6", i32* %"last"
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"for.cond"
for.cond:
  %"str.1" = load i8*, i8** %"str.addr"
  %"i.1" = load i32, i32* %"i"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %"i.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".10" = zext i8 %"ptr_load" to i32
  %".11" = icmp ne i32 %".10", 0
  br i1 %".11", label %"for.body", label %"for.end"
for.body:
  %"str.2" = load i8*, i8** %"str.addr"
  %"i.2" = load i32, i32* %"i"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.2", i32 %"i.2"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %"ch.1" = load i8, i8* %"ch.addr"
  %".13" = icmp eq i8 %"ptr_load.1", %"ch.1"
  br i1 %".13", label %"then", label %"else"
for.update:
  %"i.4" = load i32, i32* %"i"
  %".19" = add i32 %"i.4", 1
  store i32 %".19", i32* %"i"
  br label %"for.cond"
for.end:
  %"last.1" = load i32, i32* %"last"
  ret i32 %"last.1"
then:
  %"i.3" = load i32, i32* %"i"
  store i32 %"i.3", i32* %"last"
  br label %"ifcont"
else:
  br label %"ifcont"
ifcont:
  br label %"for.update"
}

define i32 @"find_any__3__byte_ptr1__byte_ptr1__int__ret_int"(i8* %"str", i8* %"char_set", i32 %"start_pos")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"char_set.addr" = alloca i8*
  store i8* %"char_set", i8** %"char_set.addr"
  %"start_pos.addr" = alloca i32
  store i32 %"start_pos", i32* %"start_pos.addr"
  %"i" = alloca i32
  %"start_pos.1" = load i32, i32* %"start_pos.addr"
  store i32 %"start_pos.1", i32* %"i"
  br label %"for.cond"
for.cond:
  %"str.1" = load i8*, i8** %"str.addr"
  %"i.1" = load i32, i32* %"i"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %"i.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".10" = zext i8 %"ptr_load" to i32
  %".11" = icmp ne i32 %".10", 0
  br i1 %".11", label %"for.body", label %"for.end"
for.body:
  %"j" = alloca i32
  store i32 0, i32* %"j"
  br label %"for.cond.1"
for.update:
  %"i.4" = load i32, i32* %"i"
  %".27" = add i32 %"i.4", 1
  store i32 %".27", i32* %"i"
  br label %"for.cond"
for.end:
  %".30" = sub i32 0, 1
  ret i32 %".30"
for.cond.1:
  %"char_set.1" = load i8*, i8** %"char_set.addr"
  %"j.1" = load i32, i32* %"j"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"char_set.1", i32 %"j.1"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".15" = zext i8 %"ptr_load.1" to i32
  %".16" = icmp ne i32 %".15", 0
  br i1 %".16", label %"for.body.1", label %"for.end.1"
for.body.1:
  %"str.2" = load i8*, i8** %"str.addr"
  %"i.2" = load i32, i32* %"i"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"str.2", i32 %"i.2"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  %"char_set.2" = load i8*, i8** %"char_set.addr"
  %"j.2" = load i32, i32* %"j"
  %"ptr_gep.3" = getelementptr inbounds i8, i8* %"char_set.2", i32 %"j.2"
  %"ptr_load.3" = load i8, i8* %"ptr_gep.3"
  %".18" = icmp eq i8 %"ptr_load.2", %"ptr_load.3"
  br i1 %".18", label %"then", label %"else"
for.update.1:
  %"j.3" = load i32, i32* %"j"
  %".23" = add i32 %"j.3", 1
  store i32 %".23", i32* %"j"
  br label %"for.cond.1"
for.end.1:
  br label %"for.update"
then:
  %"i.3" = load i32, i32* %"i"
  ret i32 %"i.3"
else:
  br label %"ifcont"
ifcont:
  br label %"for.update.1"
}

define i32 @"find_substring__3__byte_ptr1__byte_ptr1__int__ret_int"(i8* %"str", i8* %"substr", i32 %"start_pos")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"substr.addr" = alloca i8*
  store i8* %"substr", i8** %"substr.addr"
  %"start_pos.addr" = alloca i32
  store i32 %"start_pos", i32* %"start_pos.addr"
  %"str_len" = alloca i32
  store i32 0, i32* %"str_len"
  br label %"while.cond"
while.cond:
  %"str.1" = load i8*, i8** %"str.addr"
  %"str_len.1" = load i32, i32* %"str_len"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %"str_len.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".10" = zext i8 %"ptr_load" to i32
  %".11" = icmp ne i32 %".10", 0
  br i1 %".11", label %"while.body", label %"while.end"
while.body:
  %"str_len.2" = load i32, i32* %"str_len"
  %".13" = add i32 %"str_len.2", 1
  store i32 %".13", i32* %"str_len"
  br label %"while.cond"
while.end:
  %"substr_len" = alloca i32
  store i32 0, i32* %"substr_len"
  br label %"while.cond.1"
while.cond.1:
  %"substr.1" = load i8*, i8** %"substr.addr"
  %"substr_len.1" = load i32, i32* %"substr_len"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"substr.1", i32 %"substr_len.1"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".18" = zext i8 %"ptr_load.1" to i32
  %".19" = icmp ne i32 %".18", 0
  br i1 %".19", label %"while.body.1", label %"while.end.1"
while.body.1:
  %"substr_len.2" = load i32, i32* %"substr_len"
  %".21" = add i32 %"substr_len.2", 1
  store i32 %".21", i32* %"substr_len"
  br label %"while.cond.1"
while.end.1:
  %"substr_len.3" = load i32, i32* %"substr_len"
  %".24" = icmp eq i32 %"substr_len.3", 0
  br i1 %".24", label %"then", label %"else"
then:
  %"start_pos.1" = load i32, i32* %"start_pos.addr"
  ret i32 %"start_pos.1"
else:
  br label %"ifcont"
ifcont:
  %"i" = alloca i32
  %"start_pos.2" = load i32, i32* %"start_pos.addr"
  store i32 %"start_pos.2", i32* %"i"
  br label %"for.cond"
for.cond:
  %"i.1" = load i32, i32* %"i"
  %"str_len.3" = load i32, i32* %"str_len"
  %"substr_len.4" = load i32, i32* %"substr_len"
  %".30" = sub i32 %"str_len.3", %"substr_len.4"
  %".31" = icmp sle i32 %"i.1", %".30"
  br i1 %".31", label %"for.body", label %"for.end"
for.body:
  %"match" = alloca i1
  store i1 true, i1* %"match"
  %"j" = alloca i32
  store i32 0, i32* %"j"
  br label %"for.cond.1"
for.update:
  %"i.4" = load i32, i32* %"i"
  %".52" = add i32 %"i.4", 1
  store i32 %".52", i32* %"i"
  br label %"for.cond"
for.end:
  %".55" = sub i32 0, 1
  ret i32 %".55"
for.cond.1:
  %"j.1" = load i32, i32* %"j"
  %"substr_len.5" = load i32, i32* %"substr_len"
  %".36" = icmp slt i32 %"j.1", %"substr_len.5"
  br i1 %".36", label %"for.body.1", label %"for.end.1"
for.body.1:
  %"str.2" = load i8*, i8** %"str.addr"
  %"i.2" = load i32, i32* %"i"
  %"j.2" = load i32, i32* %"j"
  %".38" = add i32 %"i.2", %"j.2"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"str.2", i32 %".38"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  %"substr.2" = load i8*, i8** %"substr.addr"
  %"j.3" = load i32, i32* %"j"
  %"ptr_gep.3" = getelementptr inbounds i8, i8* %"substr.2", i32 %"j.3"
  %"ptr_load.3" = load i8, i8* %"ptr_gep.3"
  %".39" = icmp ne i8 %"ptr_load.2", %"ptr_load.3"
  br i1 %".39", label %"then.1", label %"else.1"
for.update.1:
  %"j.4" = load i32, i32* %"j"
  %".45" = add i32 %"j.4", 1
  store i32 %".45", i32* %"j"
  br label %"for.cond.1"
for.end.1:
  %"match.1" = load i1, i1* %"match"
  br i1 %"match.1", label %"then.2", label %"else.2"
then.1:
  store i1 false, i1* %"match"
  br label %"for.end.1"
else.1:
  br label %"ifcont.1"
ifcont.1:
  br label %"for.update.1"
then.2:
  %"i.3" = load i32, i32* %"i"
  ret i32 %"i.3"
else.2:
  br label %"ifcont.2"
ifcont.2:
  br label %"for.update"
}

define i32 @"skip_whitespace__2__byte_ptr1__int__ret_int"(i8* %"str", i32 %"pos")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"pos.addr" = alloca i32
  store i32 %"pos", i32* %"pos.addr"
  br label %"while.cond"
while.cond:
  %"str.1" = load i8*, i8** %"str.addr"
  %"pos.1" = load i32, i32* %"pos.addr"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %"pos.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".7" = zext i8 %"ptr_load" to i32
  %".8" = icmp ne i32 %".7", 0
  %"str.2" = load i8*, i8** %"str.addr"
  %"pos.2" = load i32, i32* %"pos.addr"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.2", i32 %"pos.2"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".9" = call i1 @"is_whitespace__1__char__ret_bool"(i8 %"ptr_load.1")
  %".10" = and i1 %".8", %".9"
  br i1 %".10", label %"while.body", label %"while.end"
while.body:
  %"pos.3" = load i32, i32* %"pos.addr"
  %".12" = add i32 %"pos.3", 1
  store i32 %".12", i32* %"pos.addr"
  br label %"while.cond"
while.end:
  %"pos.4" = load i32, i32* %"pos.addr"
  ret i32 %"pos.4"
}

define void @"trim_end__1__byte_ptr1__ret_void"(i8* %"str")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"len" = alloca i32
  store i32 0, i32* %"len"
  br label %"while.cond"
while.cond:
  %"str.1" = load i8*, i8** %"str.addr"
  %"len.1" = load i32, i32* %"len"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %"len.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".6" = zext i8 %"ptr_load" to i32
  %".7" = icmp ne i32 %".6", 0
  br i1 %".7", label %"while.body", label %"while.end"
while.body:
  %"len.2" = load i32, i32* %"len"
  %".9" = add i32 %"len.2", 1
  store i32 %".9", i32* %"len"
  br label %"while.cond"
while.end:
  br label %"while.cond.1"
while.cond.1:
  %"len.3" = load i32, i32* %"len"
  %".13" = icmp sgt i32 %"len.3", 0
  %"str.2" = load i8*, i8** %"str.addr"
  %"len.4" = load i32, i32* %"len"
  %".14" = sub i32 %"len.4", 1
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.2", i32 %".14"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".15" = call i1 @"is_whitespace__1__char__ret_bool"(i8 %"ptr_load.1")
  %".16" = and i1 %".13", %".15"
  br i1 %".16", label %"while.body.1", label %"while.end.1"
while.body.1:
  %"len.5" = load i32, i32* %"len"
  %".18" = sub i32 %"len.5", 1
  store i32 %".18", i32* %"len"
  br label %"while.cond.1"
while.end.1:
  %".21" = trunc i32 0 to i8
  %"str.3" = load i8*, i8** %"str.addr"
  %"len.6" = load i32, i32* %"len"
  %".22" = getelementptr inbounds i8, i8* %"str.3", i32 %"len.6"
  %".23" = trunc i32 0 to i8
  store i8 %".23", i8* %".22"
  ret void
}

define i32 @"compare_n__3__byte_ptr1__byte_ptr1__int__ret_int"(i8* %"s1", i8* %"s2", i32 %"n")
{
entry:
  %"s1.addr" = alloca i8*
  store i8* %"s1", i8** %"s1.addr"
  %"s2.addr" = alloca i8*
  store i8* %"s2", i8** %"s2.addr"
  %"n.addr" = alloca i32
  store i32 %"n", i32* %"n.addr"
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"for.cond"
for.cond:
  %"i.1" = load i32, i32* %"i"
  %"n.1" = load i32, i32* %"n.addr"
  %".10" = icmp slt i32 %"i.1", %"n.1"
  br i1 %".10", label %"for.body", label %"for.end"
for.body:
  %"s1.1" = load i8*, i8** %"s1.addr"
  %"i.2" = load i32, i32* %"i"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"s1.1", i32 %"i.2"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %"s2.1" = load i8*, i8** %"s2.addr"
  %"i.3" = load i32, i32* %"i"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"s2.1", i32 %"i.3"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".12" = icmp ne i8 %"ptr_load", %"ptr_load.1"
  br i1 %".12", label %"then", label %"else"
for.update:
  %"i.7" = load i32, i32* %"i"
  %".24" = add i32 %"i.7", 1
  store i32 %".24", i32* %"i"
  br label %"for.cond"
for.end:
  ret i32 0
then:
  %"s1.2" = load i8*, i8** %"s1.addr"
  %"i.4" = load i32, i32* %"i"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"s1.2", i32 %"i.4"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  %"s2.2" = load i8*, i8** %"s2.addr"
  %"i.5" = load i32, i32* %"i"
  %"ptr_gep.3" = getelementptr inbounds i8, i8* %"s2.2", i32 %"i.5"
  %"ptr_load.3" = load i8, i8* %"ptr_gep.3"
  %".14" = sub i8 %"ptr_load.2", %"ptr_load.3"
  %".15" = sext i8 %".14" to i32
  ret i32 %".15"
else:
  br label %"ifcont"
ifcont:
  %"s1.3" = load i8*, i8** %"s1.addr"
  %"i.6" = load i32, i32* %"i"
  %"ptr_gep.4" = getelementptr inbounds i8, i8* %"s1.3", i32 %"i.6"
  %"ptr_load.4" = load i8, i8* %"ptr_gep.4"
  %".18" = zext i8 %"ptr_load.4" to i32
  %".19" = icmp eq i32 %".18", 0
  br i1 %".19", label %"then.1", label %"else.1"
then.1:
  ret i32 0
else.1:
  br label %"ifcont.1"
ifcont.1:
  br label %"for.update"
}

define i32 @"compare_ignore_case__2__byte_ptr1__byte_ptr1__ret_int"(i8* %"s1", i8* %"s2")
{
entry:
  %"s1.addr" = alloca i8*
  store i8* %"s1", i8** %"s1.addr"
  %"s2.addr" = alloca i8*
  store i8* %"s2", i8** %"s2.addr"
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"while.cond"
while.cond:
  %"s1.1" = load i8*, i8** %"s1.addr"
  %"i.1" = load i32, i32* %"i"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"s1.1", i32 %"i.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".8" = zext i8 %"ptr_load" to i32
  %".9" = icmp ne i32 %".8", 0
  %"s2.1" = load i8*, i8** %"s2.addr"
  %"i.2" = load i32, i32* %"i"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"s2.1", i32 %"i.2"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".10" = zext i8 %"ptr_load.1" to i32
  %".11" = icmp ne i32 %".10", 0
  %".12" = and i1 %".9", %".11"
  br i1 %".12", label %"while.body", label %"while.end"
while.body:
  %"c1" = alloca i8
  %"s1.2" = load i8*, i8** %"s1.addr"
  %"i.3" = load i32, i32* %"i"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"s1.2", i32 %"i.3"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  %".14" = call i8 @"to_lower__1__char__ret_char"(i8 %"ptr_load.2")
  store i8 %".14", i8* %"c1"
  %"c2" = alloca i8
  %"s2.2" = load i8*, i8** %"s2.addr"
  %"i.4" = load i32, i32* %"i"
  %"ptr_gep.3" = getelementptr inbounds i8, i8* %"s2.2", i32 %"i.4"
  %"ptr_load.3" = load i8, i8* %"ptr_gep.3"
  %".16" = call i8 @"to_lower__1__char__ret_char"(i8 %"ptr_load.3")
  store i8 %".16", i8* %"c2"
  %"c1.1" = load i8, i8* %"c1"
  %"c2.1" = load i8, i8* %"c2"
  %".18" = icmp ne i8 %"c1.1", %"c2.1"
  br i1 %".18", label %"then", label %"else"
while.end:
  %"s1.3" = load i8*, i8** %"s1.addr"
  %"i.6" = load i32, i32* %"i"
  %"ptr_gep.4" = getelementptr inbounds i8, i8* %"s1.3", i32 %"i.6"
  %"ptr_load.4" = load i8, i8* %"ptr_gep.4"
  %".27" = call i8 @"to_lower__1__char__ret_char"(i8 %"ptr_load.4")
  %"s2.3" = load i8*, i8** %"s2.addr"
  %"i.7" = load i32, i32* %"i"
  %"ptr_gep.5" = getelementptr inbounds i8, i8* %"s2.3", i32 %"i.7"
  %"ptr_load.5" = load i8, i8* %"ptr_gep.5"
  %".28" = call i8 @"to_lower__1__char__ret_char"(i8 %"ptr_load.5")
  %".29" = sub i8 %".27", %".28"
  %".30" = sext i8 %".29" to i32
  ret i32 %".30"
then:
  %"c1.2" = load i8, i8* %"c1"
  %"c2.2" = load i8, i8* %"c2"
  %".20" = sub i8 %"c1.2", %"c2.2"
  %".21" = sext i8 %".20" to i32
  ret i32 %".21"
else:
  br label %"ifcont"
ifcont:
  %"i.5" = load i32, i32* %"i"
  %".24" = add i32 %"i.5", 1
  store i32 %".24", i32* %"i"
  br label %"while.cond"
}

define i1 @"starts_with__2__byte_ptr1__byte_ptr1__ret_bool"(i8* %"str", i8* %"prefix")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"prefix.addr" = alloca i8*
  store i8* %"prefix", i8** %"prefix.addr"
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"while.cond"
while.cond:
  %"prefix.1" = load i8*, i8** %"prefix.addr"
  %"i.1" = load i32, i32* %"i"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"prefix.1", i32 %"i.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".8" = zext i8 %"ptr_load" to i32
  %".9" = icmp ne i32 %".8", 0
  br i1 %".9", label %"while.body", label %"while.end"
while.body:
  %"str.1" = load i8*, i8** %"str.addr"
  %"i.2" = load i32, i32* %"i"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.1", i32 %"i.2"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %"prefix.2" = load i8*, i8** %"prefix.addr"
  %"i.3" = load i32, i32* %"i"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"prefix.2", i32 %"i.3"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  %".11" = icmp ne i8 %"ptr_load.1", %"ptr_load.2"
  br i1 %".11", label %"then", label %"else"
while.end:
  ret i1 true
then:
  ret i1 false
else:
  br label %"ifcont"
ifcont:
  %"i.4" = load i32, i32* %"i"
  %".15" = add i32 %"i.4", 1
  store i32 %".15", i32* %"i"
  br label %"while.cond"
}

define i1 @"ends_with__2__byte_ptr1__byte_ptr1__ret_bool"(i8* %"str", i8* %"suffix")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"suffix.addr" = alloca i8*
  store i8* %"suffix", i8** %"suffix.addr"
  %"str_len" = alloca i32
  store i32 0, i32* %"str_len"
  br label %"while.cond"
while.cond:
  %"str.1" = load i8*, i8** %"str.addr"
  %"str_len.1" = load i32, i32* %"str_len"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %"str_len.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".8" = zext i8 %"ptr_load" to i32
  %".9" = icmp ne i32 %".8", 0
  br i1 %".9", label %"while.body", label %"while.end"
while.body:
  %"str_len.2" = load i32, i32* %"str_len"
  %".11" = add i32 %"str_len.2", 1
  store i32 %".11", i32* %"str_len"
  br label %"while.cond"
while.end:
  %"suffix_len" = alloca i32
  store i32 0, i32* %"suffix_len"
  br label %"while.cond.1"
while.cond.1:
  %"suffix.1" = load i8*, i8** %"suffix.addr"
  %"suffix_len.1" = load i32, i32* %"suffix_len"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"suffix.1", i32 %"suffix_len.1"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".16" = zext i8 %"ptr_load.1" to i32
  %".17" = icmp ne i32 %".16", 0
  br i1 %".17", label %"while.body.1", label %"while.end.1"
while.body.1:
  %"suffix_len.2" = load i32, i32* %"suffix_len"
  %".19" = add i32 %"suffix_len.2", 1
  store i32 %".19", i32* %"suffix_len"
  br label %"while.cond.1"
while.end.1:
  %"suffix_len.3" = load i32, i32* %"suffix_len"
  %"str_len.3" = load i32, i32* %"str_len"
  %".22" = icmp sgt i32 %"suffix_len.3", %"str_len.3"
  br i1 %".22", label %"then", label %"else"
then:
  ret i1 false
else:
  br label %"ifcont"
ifcont:
  %"offset" = alloca i32
  %"str_len.4" = load i32, i32* %"str_len"
  %"suffix_len.4" = load i32, i32* %"suffix_len"
  %".26" = sub i32 %"str_len.4", %"suffix_len.4"
  store i32 %".26", i32* %"offset"
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"for.cond"
for.cond:
  %"i.1" = load i32, i32* %"i"
  %"suffix_len.5" = load i32, i32* %"suffix_len"
  %".30" = icmp slt i32 %"i.1", %"suffix_len.5"
  br i1 %".30", label %"for.body", label %"for.end"
for.body:
  %"str.2" = load i8*, i8** %"str.addr"
  %"offset.1" = load i32, i32* %"offset"
  %"i.2" = load i32, i32* %"i"
  %".32" = add i32 %"offset.1", %"i.2"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"str.2", i32 %".32"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  %"suffix.2" = load i8*, i8** %"suffix.addr"
  %"i.3" = load i32, i32* %"i"
  %"ptr_gep.3" = getelementptr inbounds i8, i8* %"suffix.2", i32 %"i.3"
  %"ptr_load.3" = load i8, i8* %"ptr_gep.3"
  %".33" = icmp ne i8 %"ptr_load.2", %"ptr_load.3"
  br i1 %".33", label %"then.1", label %"else.1"
for.update:
  %"i.4" = load i32, i32* %"i"
  %".38" = add i32 %"i.4", 1
  store i32 %".38", i32* %"i"
  br label %"for.cond"
for.end:
  ret i1 true
then.1:
  ret i1 false
else.1:
  br label %"ifcont.1"
ifcont.1:
  br label %"for.update"
}

define i8* @"copy_string__1__byte_ptr1__ret_byte"(i8* %"src")
{
entry:
  %"src.addr" = alloca i8*
  store i8* %"src", i8** %"src.addr"
  %"len" = alloca i32
  store i32 0, i32* %"len"
  br label %"while.cond"
while.cond:
  %"src.1" = load i8*, i8** %"src.addr"
  %"len.1" = load i32, i32* %"len"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"src.1", i32 %"len.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".6" = zext i8 %"ptr_load" to i32
  %".7" = icmp ne i32 %".6", 0
  br i1 %".7", label %"while.body", label %"while.end"
while.body:
  %"len.2" = load i32, i32* %"len"
  %".9" = add i32 %"len.2", 1
  store i32 %".9", i32* %"len"
  br label %"while.cond"
while.end:
  %"dest" = alloca i8*
  %"len.3" = load i32, i32* %"len"
  %".12" = zext i32 %"len.3" to i64
  %".13" = zext i32 1 to i64
  %".14" = add i64 %".12", %".13"
  %".15" = call i8* @"malloc"(i64 %".14")
  store i8* %".15", i8** %"dest"
  %"dest.1" = load i8*, i8** %"dest"
  %".17" = ptrtoint i8* %"dest.1" to i64
  %".18" = icmp eq i64 %".17", 0
  br i1 %".18", label %"then", label %"else"
then:
  %"int_to_ptr" = inttoptr i32 0 to i8*
  ret i8* %"int_to_ptr"
else:
  br label %"ifcont"
ifcont:
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"for.cond"
for.cond:
  %"i.1" = load i32, i32* %"i"
  %"len.4" = load i32, i32* %"len"
  %".24" = icmp sle i32 %"i.1", %"len.4"
  br i1 %".24", label %"for.body", label %"for.end"
for.body:
  %"src.2" = load i8*, i8** %"src.addr"
  %"i.2" = load i32, i32* %"i"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"src.2", i32 %"i.2"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %"dest.2" = load i8*, i8** %"dest"
  %"i.3" = load i32, i32* %"i"
  %".26" = getelementptr inbounds i8, i8* %"dest.2", i32 %"i.3"
  %"src.3" = load i8*, i8** %"src.addr"
  %"i.4" = load i32, i32* %"i"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"src.3", i32 %"i.4"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  store i8 %"ptr_load.2", i8* %".26"
  br label %"for.update"
for.update:
  %"i.5" = load i32, i32* %"i"
  %".29" = add i32 %"i.5", 1
  store i32 %".29", i32* %"i"
  br label %"for.cond"
for.end:
  %"dest.3" = load i8*, i8** %"dest"
  ret i8* %"dest.3"
}

define i8* @"copy_n__2__byte_ptr1__int__ret_byte"(i8* %"src", i32 %"n")
{
entry:
  %"src.addr" = alloca i8*
  store i8* %"src", i8** %"src.addr"
  %"n.addr" = alloca i32
  store i32 %"n", i32* %"n.addr"
  %"dest" = alloca i8*
  %"n.1" = load i32, i32* %"n.addr"
  %".6" = zext i32 %"n.1" to i64
  %".7" = zext i32 1 to i64
  %".8" = add i64 %".6", %".7"
  %".9" = call i8* @"malloc"(i64 %".8")
  store i8* %".9", i8** %"dest"
  %"dest.1" = load i8*, i8** %"dest"
  %".11" = ptrtoint i8* %"dest.1" to i64
  %".12" = icmp eq i64 %".11", 0
  br i1 %".12", label %"then", label %"else"
then:
  %"int_to_ptr" = inttoptr i32 0 to i8*
  ret i8* %"int_to_ptr"
else:
  br label %"ifcont"
ifcont:
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"for.cond"
for.cond:
  %"i.1" = load i32, i32* %"i"
  %"n.2" = load i32, i32* %"n.addr"
  %".18" = icmp slt i32 %"i.1", %"n.2"
  %"src.1" = load i8*, i8** %"src.addr"
  %"i.2" = load i32, i32* %"i"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"src.1", i32 %"i.2"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".19" = zext i8 %"ptr_load" to i32
  %".20" = icmp ne i32 %".19", 0
  %".21" = and i1 %".18", %".20"
  br i1 %".21", label %"for.body", label %"for.end"
for.body:
  %"src.2" = load i8*, i8** %"src.addr"
  %"i.3" = load i32, i32* %"i"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"src.2", i32 %"i.3"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %"dest.2" = load i8*, i8** %"dest"
  %"i.4" = load i32, i32* %"i"
  %".23" = getelementptr inbounds i8, i8* %"dest.2", i32 %"i.4"
  %"src.3" = load i8*, i8** %"src.addr"
  %"i.5" = load i32, i32* %"i"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"src.3", i32 %"i.5"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  store i8 %"ptr_load.2", i8* %".23"
  br label %"for.update"
for.update:
  %"i.6" = load i32, i32* %"i"
  %".26" = add i32 %"i.6", 1
  store i32 %".26", i32* %"i"
  br label %"for.cond"
for.end:
  %".29" = trunc i32 0 to i8
  %"dest.3" = load i8*, i8** %"dest"
  %"n.3" = load i32, i32* %"n.addr"
  %".30" = getelementptr inbounds i8, i8* %"dest.3", i32 %"n.3"
  %".31" = trunc i32 0 to i8
  store i8 %".31", i8* %".30"
  %"dest.4" = load i8*, i8** %"dest"
  ret i8* %"dest.4"
}

define i8* @"substring__3__byte_ptr1__int__int__ret_byte"(i8* %"str", i32 %"start", i32 %"length")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"start.addr" = alloca i32
  store i32 %"start", i32* %"start.addr"
  %"length.addr" = alloca i32
  store i32 %"length", i32* %"length.addr"
  %"result" = alloca i8*
  %"length.1" = load i32, i32* %"length.addr"
  %".8" = zext i32 %"length.1" to i64
  %".9" = zext i32 1 to i64
  %".10" = add i64 %".8", %".9"
  %".11" = call i8* @"malloc"(i64 %".10")
  store i8* %".11", i8** %"result"
  %"result.1" = load i8*, i8** %"result"
  %".13" = ptrtoint i8* %"result.1" to i64
  %".14" = icmp eq i64 %".13", 0
  br i1 %".14", label %"then", label %"else"
then:
  %"int_to_ptr" = inttoptr i32 0 to i8*
  ret i8* %"int_to_ptr"
else:
  br label %"ifcont"
ifcont:
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"for.cond"
for.cond:
  %"i.1" = load i32, i32* %"i"
  %"length.2" = load i32, i32* %"length.addr"
  %".20" = icmp slt i32 %"i.1", %"length.2"
  %"str.1" = load i8*, i8** %"str.addr"
  %"start.1" = load i32, i32* %"start.addr"
  %"i.2" = load i32, i32* %"i"
  %".21" = add i32 %"start.1", %"i.2"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %".21"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".22" = zext i8 %"ptr_load" to i32
  %".23" = icmp ne i32 %".22", 0
  %".24" = and i1 %".20", %".23"
  br i1 %".24", label %"for.body", label %"for.end"
for.body:
  %"str.2" = load i8*, i8** %"str.addr"
  %"start.2" = load i32, i32* %"start.addr"
  %"i.3" = load i32, i32* %"i"
  %".26" = add i32 %"start.2", %"i.3"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.2", i32 %".26"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %"result.2" = load i8*, i8** %"result"
  %"i.4" = load i32, i32* %"i"
  %".27" = getelementptr inbounds i8, i8* %"result.2", i32 %"i.4"
  %"str.3" = load i8*, i8** %"str.addr"
  %"start.3" = load i32, i32* %"start.addr"
  %"i.5" = load i32, i32* %"i"
  %".28" = add i32 %"start.3", %"i.5"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"str.3", i32 %".28"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  store i8 %"ptr_load.2", i8* %".27"
  br label %"for.update"
for.update:
  %"i.6" = load i32, i32* %"i"
  %".31" = add i32 %"i.6", 1
  store i32 %".31", i32* %"i"
  br label %"for.cond"
for.end:
  %".34" = trunc i32 0 to i8
  %"result.3" = load i8*, i8** %"result"
  %"length.3" = load i32, i32* %"length.addr"
  %".35" = getelementptr inbounds i8, i8* %"result.3", i32 %"length.3"
  %".36" = trunc i32 0 to i8
  store i8 %".36", i8* %".35"
  %"result.4" = load i8*, i8** %"result"
  ret i8* %"result.4"
}

define i8* @"concat__2__byte_ptr1__byte_ptr1__ret_byte"(i8* %"s1", i8* %"s2")
{
entry:
  %"s1.addr" = alloca i8*
  store i8* %"s1", i8** %"s1.addr"
  %"s2.addr" = alloca i8*
  store i8* %"s2", i8** %"s2.addr"
  %"len1" = alloca i32
  store i32 0, i32* %"len1"
  br label %"while.cond"
while.cond:
  %"s1.1" = load i8*, i8** %"s1.addr"
  %"len1.1" = load i32, i32* %"len1"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"s1.1", i32 %"len1.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".8" = zext i8 %"ptr_load" to i32
  %".9" = icmp ne i32 %".8", 0
  br i1 %".9", label %"while.body", label %"while.end"
while.body:
  %"len1.2" = load i32, i32* %"len1"
  %".11" = add i32 %"len1.2", 1
  store i32 %".11", i32* %"len1"
  br label %"while.cond"
while.end:
  %"len2" = alloca i32
  store i32 0, i32* %"len2"
  br label %"while.cond.1"
while.cond.1:
  %"s2.1" = load i8*, i8** %"s2.addr"
  %"len2.1" = load i32, i32* %"len2"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"s2.1", i32 %"len2.1"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".16" = zext i8 %"ptr_load.1" to i32
  %".17" = icmp ne i32 %".16", 0
  br i1 %".17", label %"while.body.1", label %"while.end.1"
while.body.1:
  %"len2.2" = load i32, i32* %"len2"
  %".19" = add i32 %"len2.2", 1
  store i32 %".19", i32* %"len2"
  br label %"while.cond.1"
while.end.1:
  %"result" = alloca i8*
  %"len1.3" = load i32, i32* %"len1"
  %".22" = zext i32 %"len1.3" to i64
  %"len2.3" = load i32, i32* %"len2"
  %".23" = zext i32 %"len2.3" to i64
  %".24" = add i64 %".22", %".23"
  %".25" = zext i32 1 to i64
  %".26" = add i64 %".24", %".25"
  %".27" = call i8* @"malloc"(i64 %".26")
  store i8* %".27", i8** %"result"
  %"result.1" = load i8*, i8** %"result"
  %".29" = ptrtoint i8* %"result.1" to i64
  %".30" = icmp eq i64 %".29", 0
  br i1 %".30", label %"then", label %"else"
then:
  %"int_to_ptr" = inttoptr i32 0 to i8*
  ret i8* %"int_to_ptr"
else:
  br label %"ifcont"
ifcont:
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"for.cond"
for.cond:
  %"i.1" = load i32, i32* %"i"
  %"len1.4" = load i32, i32* %"len1"
  %".36" = icmp slt i32 %"i.1", %"len1.4"
  br i1 %".36", label %"for.body", label %"for.end"
for.body:
  %"s1.2" = load i8*, i8** %"s1.addr"
  %"i.2" = load i32, i32* %"i"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"s1.2", i32 %"i.2"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  %"result.2" = load i8*, i8** %"result"
  %"i.3" = load i32, i32* %"i"
  %".38" = getelementptr inbounds i8, i8* %"result.2", i32 %"i.3"
  %"s1.3" = load i8*, i8** %"s1.addr"
  %"i.4" = load i32, i32* %"i"
  %"ptr_gep.3" = getelementptr inbounds i8, i8* %"s1.3", i32 %"i.4"
  %"ptr_load.3" = load i8, i8* %"ptr_gep.3"
  store i8 %"ptr_load.3", i8* %".38"
  br label %"for.update"
for.update:
  %"i.5" = load i32, i32* %"i"
  %".41" = add i32 %"i.5", 1
  store i32 %".41", i32* %"i"
  br label %"for.cond"
for.end:
  %"i.6" = alloca i32
  store i32 0, i32* %"i.6"
  br label %"for.cond.1"
for.cond.1:
  %"i.7" = load i32, i32* %"i.6"
  %"len2.4" = load i32, i32* %"len2"
  %".46" = icmp slt i32 %"i.7", %"len2.4"
  br i1 %".46", label %"for.body.1", label %"for.end.1"
for.body.1:
  %"s2.2" = load i8*, i8** %"s2.addr"
  %"i.8" = load i32, i32* %"i.6"
  %"ptr_gep.4" = getelementptr inbounds i8, i8* %"s2.2", i32 %"i.8"
  %"ptr_load.4" = load i8, i8* %"ptr_gep.4"
  %"result.3" = load i8*, i8** %"result"
  %"len1.5" = load i32, i32* %"len1"
  %"i.9" = load i32, i32* %"i.6"
  %".48" = add i32 %"len1.5", %"i.9"
  %".49" = getelementptr inbounds i8, i8* %"result.3", i32 %".48"
  %"s2.3" = load i8*, i8** %"s2.addr"
  %"i.10" = load i32, i32* %"i.6"
  %"ptr_gep.5" = getelementptr inbounds i8, i8* %"s2.3", i32 %"i.10"
  %"ptr_load.5" = load i8, i8* %"ptr_gep.5"
  store i8 %"ptr_load.5", i8* %".49"
  br label %"for.update.1"
for.update.1:
  %"i.11" = load i32, i32* %"i.6"
  %".52" = add i32 %"i.11", 1
  store i32 %".52", i32* %"i.6"
  br label %"for.cond.1"
for.end.1:
  %".55" = trunc i32 0 to i8
  %"result.4" = load i8*, i8** %"result"
  %"len1.6" = load i32, i32* %"len1"
  %"len2.5" = load i32, i32* %"len2"
  %".56" = add i32 %"len1.6", %"len2.5"
  %".57" = getelementptr inbounds i8, i8* %"result.4", i32 %".56"
  %".58" = trunc i32 0 to i8
  store i8 %".58", i8* %".57"
  %"result.5" = load i8*, i8** %"result"
  ret i8* %"result.5"
}

define i32 @"parse_int__3__byte_ptr1__int__int_ptr1__ret_int"(i8* %"str", i32 %"start_pos", i32* %"end_pos")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"start_pos.addr" = alloca i32
  store i32 %"start_pos", i32* %"start_pos.addr"
  %"end_pos.addr" = alloca i32*
  store i32* %"end_pos", i32** %"end_pos.addr"
  %"pos" = alloca i32
  %"str.1" = load i8*, i8** %"str.addr"
  %"start_pos.1" = load i32, i32* %"start_pos.addr"
  %".8" = call i32 @"skip_whitespace__2__byte_ptr1__int__ret_int"(i8* %"str.1", i32 %"start_pos.1")
  store i32 %".8", i32* %"pos"
  %"negative" = alloca i1
  store i1 false, i1* %"negative"
  %"str.2" = load i8*, i8** %"str.addr"
  %"pos.1" = load i32, i32* %"pos"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.2", i32 %"pos.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".11" = icmp eq i8 %"ptr_load", 45
  br i1 %".11", label %"then", label %"else"
then:
  store i1 true, i1* %"negative"
  %"pos.2" = load i32, i32* %"pos"
  %".14" = add i32 %"pos.2", 1
  store i32 %".14", i32* %"pos"
  br label %"ifcont"
else:
  %"str.3" = load i8*, i8** %"str.addr"
  %"pos.3" = load i32, i32* %"pos"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.3", i32 %"pos.3"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".17" = icmp eq i8 %"ptr_load.1", 43
  br i1 %".17", label %"elif_then_0", label %"elif_else_0"
ifcont:
  %"value" = alloca i32
  store i32 0, i32* %"value"
  br label %"while.cond"
elif_then_0:
  %"pos.4" = load i32, i32* %"pos"
  %".19" = add i32 %"pos.4", 1
  store i32 %".19", i32* %"pos"
  br label %"ifcont"
elif_else_0:
  br label %"ifcont"
while.cond:
  %"str.4" = load i8*, i8** %"str.addr"
  %"pos.5" = load i32, i32* %"pos"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"str.4", i32 %"pos.5"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  %".25" = call i1 @"is_digit__1__char__ret_bool"(i8 %"ptr_load.2")
  br i1 %".25", label %"while.body", label %"while.end"
while.body:
  %"value.1" = load i32, i32* %"value"
  %".27" = mul i32 %"value.1", 10
  %"str.5" = load i8*, i8** %"str.addr"
  %"pos.6" = load i32, i32* %"pos"
  %"ptr_gep.3" = getelementptr inbounds i8, i8* %"str.5", i32 %"pos.6"
  %"ptr_load.3" = load i8, i8* %"ptr_gep.3"
  %".28" = sub i8 %"ptr_load.3", 48
  %".29" = zext i8 %".28" to i32
  %".30" = add i32 %".27", %".29"
  store i32 %".30", i32* %"value"
  %"pos.7" = load i32, i32* %"pos"
  %".32" = add i32 %"pos.7", 1
  store i32 %".32", i32* %"pos"
  br label %"while.cond"
while.end:
  %"pos.8" = load i32, i32* %"pos"
  %"end_pos.1" = load i32*, i32** %"end_pos.addr"
  store i32 %"pos.8", i32* %"end_pos.1"
  %"negative.1" = load i1, i1* %"negative"
  br i1 %"negative.1", label %"then.1", label %"else.1"
then.1:
  %"value.2" = load i32, i32* %"value"
  %".37" = sub i32 0, %"value.2"
  ret i32 %".37"
else.1:
  br label %"ifcont.1"
ifcont.1:
  %"value.3" = load i32, i32* %"value"
  ret i32 %"value.3"
}

define i32 @"parse_hex__3__byte_ptr1__int__int_ptr1__ret_int"(i8* %"str", i32 %"start_pos", i32* %"end_pos")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"start_pos.addr" = alloca i32
  store i32 %"start_pos", i32* %"start_pos.addr"
  %"end_pos.addr" = alloca i32*
  store i32* %"end_pos", i32** %"end_pos.addr"
  %"pos" = alloca i32
  %"str.1" = load i8*, i8** %"str.addr"
  %"start_pos.1" = load i32, i32* %"start_pos.addr"
  %".8" = call i32 @"skip_whitespace__2__byte_ptr1__int__ret_int"(i8* %"str.1", i32 %"start_pos.1")
  store i32 %".8", i32* %"pos"
  %"str.2" = load i8*, i8** %"str.addr"
  %"pos.1" = load i32, i32* %"pos"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.2", i32 %"pos.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".10" = icmp eq i8 %"ptr_load", 48
  %"str.3" = load i8*, i8** %"str.addr"
  %"pos.2" = load i32, i32* %"pos"
  %".11" = add i32 %"pos.2", 1
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.3", i32 %".11"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".12" = icmp eq i8 %"ptr_load.1", 120
  %"str.4" = load i8*, i8** %"str.addr"
  %"pos.3" = load i32, i32* %"pos"
  %".13" = add i32 %"pos.3", 1
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"str.4", i32 %".13"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  %".14" = icmp eq i8 %"ptr_load.2", 88
  %".15" = or i1 %".12", %".14"
  %".16" = and i1 %".10", %".15"
  br i1 %".16", label %"then", label %"else"
then:
  %"pos.4" = load i32, i32* %"pos"
  %".18" = add i32 %"pos.4", 2
  store i32 %".18", i32* %"pos"
  br label %"ifcont"
else:
  br label %"ifcont"
ifcont:
  %"value" = alloca i32
  store i32 0, i32* %"value"
  br label %"while.cond"
while.cond:
  %"str.5" = load i8*, i8** %"str.addr"
  %"pos.5" = load i32, i32* %"pos"
  %"ptr_gep.3" = getelementptr inbounds i8, i8* %"str.5", i32 %"pos.5"
  %"ptr_load.3" = load i8, i8* %"ptr_gep.3"
  %".24" = call i1 @"is_hex_digit__1__char__ret_bool"(i8 %"ptr_load.3")
  br i1 %".24", label %"while.body", label %"while.end"
while.body:
  %"digit" = alloca i32
  %"str.6" = load i8*, i8** %"str.addr"
  %"pos.6" = load i32, i32* %"pos"
  %"ptr_gep.4" = getelementptr inbounds i8, i8* %"str.6", i32 %"pos.6"
  %"ptr_load.4" = load i8, i8* %"ptr_gep.4"
  %".26" = call i32 @"hex_to_int__1__char__ret_int"(i8 %"ptr_load.4")
  store i32 %".26", i32* %"digit"
  %"value.1" = load i32, i32* %"value"
  %".28" = mul i32 %"value.1", 16
  %"digit.1" = load i32, i32* %"digit"
  %".29" = add i32 %".28", %"digit.1"
  store i32 %".29", i32* %"value"
  %"pos.7" = load i32, i32* %"pos"
  %".31" = add i32 %"pos.7", 1
  store i32 %".31", i32* %"pos"
  br label %"while.cond"
while.end:
  %"pos.8" = load i32, i32* %"pos"
  %"end_pos.1" = load i32*, i32** %"end_pos.addr"
  store i32 %"pos.8", i32* %"end_pos.1"
  %"value.2" = load i32, i32* %"value"
  ret i32 %"value.2"
}

define i32 @"count_lines__1__byte_ptr1__ret_int"(i8* %"str")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"count" = alloca i32
  store i32 0, i32* %"count"
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"for.cond"
for.cond:
  %"str.1" = load i8*, i8** %"str.addr"
  %"i.1" = load i32, i32* %"i"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %"i.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".7" = zext i8 %"ptr_load" to i32
  %".8" = icmp ne i32 %".7", 0
  br i1 %".8", label %"for.body", label %"for.end"
for.body:
  %"str.2" = load i8*, i8** %"str.addr"
  %"i.2" = load i32, i32* %"i"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.2", i32 %"i.2"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".10" = icmp eq i8 %"ptr_load.1", 10
  br i1 %".10", label %"then", label %"else"
for.update:
  %"i.3" = load i32, i32* %"i"
  %".17" = add i32 %"i.3", 1
  store i32 %".17", i32* %"i"
  br label %"for.cond"
for.end:
  %"count.2" = load i32, i32* %"count"
  %".20" = icmp sgt i32 %"count.2", 0
  %"str.3" = load i8*, i8** %"str.addr"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"str.3", i32 0
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  %".21" = zext i8 %"ptr_load.2" to i32
  %".22" = icmp ne i32 %".21", 0
  %".23" = or i1 %".20", %".22"
  br i1 %".23", label %"then.1", label %"else.1"
then:
  %"count.1" = load i32, i32* %"count"
  %".12" = add i32 %"count.1", 1
  store i32 %".12", i32* %"count"
  br label %"ifcont"
else:
  br label %"ifcont"
ifcont:
  br label %"for.update"
then.1:
  %"count.3" = load i32, i32* %"count"
  %".25" = add i32 %"count.3", 1
  store i32 %".25", i32* %"count"
  br label %"ifcont.1"
else.1:
  br label %"ifcont.1"
ifcont.1:
  %"count.4" = load i32, i32* %"count"
  ret i32 %"count.4"
}

define i8* @"get_line__2__byte_ptr1__int__ret_byte"(i8* %"str", i32 %"line_num")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"line_num.addr" = alloca i32
  store i32 %"line_num", i32* %"line_num.addr"
  %"current_line" = alloca i32
  store i32 0, i32* %"current_line"
  %"line_start" = alloca i32
  store i32 0, i32* %"line_start"
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"for.cond"
for.cond:
  %"str.1" = load i8*, i8** %"str.addr"
  %"i.1" = load i32, i32* %"i"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %"i.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".10" = zext i8 %"ptr_load" to i32
  %".11" = icmp ne i32 %".10", 0
  br i1 %".11", label %"for.body", label %"for.end"
for.body:
  %"current_line.1" = load i32, i32* %"current_line"
  %"line_num.1" = load i32, i32* %"line_num.addr"
  %".13" = icmp eq i32 %"current_line.1", %"line_num.1"
  br i1 %".13", label %"then", label %"else"
for.update:
  %"i.4" = load i32, i32* %"i"
  %".25" = add i32 %"i.4", 1
  store i32 %".25", i32* %"i"
  br label %"for.cond"
for.end:
  %"current_line.3" = load i32, i32* %"current_line"
  %"line_num.2" = load i32, i32* %"line_num.addr"
  %".28" = icmp ne i32 %"current_line.3", %"line_num.2"
  br i1 %".28", label %"then.2", label %"else.2"
then:
  %"i.2" = load i32, i32* %"i"
  store i32 %"i.2", i32* %"line_start"
  br label %"for.end"
else:
  br label %"ifcont"
ifcont:
  %"str.2" = load i8*, i8** %"str.addr"
  %"i.3" = load i32, i32* %"i"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.2", i32 %"i.3"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".18" = icmp eq i8 %"ptr_load.1", 10
  br i1 %".18", label %"then.1", label %"else.1"
then.1:
  %"current_line.2" = load i32, i32* %"current_line"
  %".20" = add i32 %"current_line.2", 1
  store i32 %".20", i32* %"current_line"
  br label %"ifcont.1"
else.1:
  br label %"ifcont.1"
ifcont.1:
  br label %"for.update"
then.2:
  %"int_to_ptr" = inttoptr i32 0 to i8*
  ret i8* %"int_to_ptr"
else.2:
  br label %"ifcont.2"
ifcont.2:
  %"line_end" = alloca i32
  %"line_start.1" = load i32, i32* %"line_start"
  store i32 %"line_start.1", i32* %"line_end"
  br label %"while.cond"
while.cond:
  %"str.3" = load i8*, i8** %"str.addr"
  %"line_end.1" = load i32, i32* %"line_end"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"str.3", i32 %"line_end.1"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  %".34" = zext i8 %"ptr_load.2" to i32
  %".35" = icmp ne i32 %".34", 0
  %"str.4" = load i8*, i8** %"str.addr"
  %"line_end.2" = load i32, i32* %"line_end"
  %"ptr_gep.3" = getelementptr inbounds i8, i8* %"str.4", i32 %"line_end.2"
  %"ptr_load.3" = load i8, i8* %"ptr_gep.3"
  %".36" = icmp ne i8 %"ptr_load.3", 10
  %".37" = and i1 %".35", %".36"
  br i1 %".37", label %"while.body", label %"while.end"
while.body:
  %"line_end.3" = load i32, i32* %"line_end"
  %".39" = add i32 %"line_end.3", 1
  store i32 %".39", i32* %"line_end"
  br label %"while.cond"
while.end:
  %"line_len" = alloca i32
  %"line_end.4" = load i32, i32* %"line_end"
  %"line_start.2" = load i32, i32* %"line_start"
  %".42" = sub i32 %"line_end.4", %"line_start.2"
  store i32 %".42", i32* %"line_len"
  %"str.5" = load i8*, i8** %"str.addr"
  %"line_start.3" = load i32, i32* %"line_start"
  %"line_len.1" = load i32, i32* %"line_len"
  %".44" = call i8* @"substring__3__byte_ptr1__int__int__ret_byte"(i8* %"str.5", i32 %"line_start.3", i32 %"line_len.1")
  ret i8* %".44"
}

define i32 @"count_words__1__byte_ptr1__ret_int"(i8* %"str")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"count" = alloca i32
  store i32 0, i32* %"count"
  %"in_word" = alloca i1
  store i1 false, i1* %"in_word"
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"for.cond"
for.cond:
  %"str.1" = load i8*, i8** %"str.addr"
  %"i.1" = load i32, i32* %"i"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %"i.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".8" = zext i8 %"ptr_load" to i32
  %".9" = icmp ne i32 %".8", 0
  br i1 %".9", label %"for.body", label %"for.end"
for.body:
  %"str.2" = load i8*, i8** %"str.addr"
  %"i.2" = load i32, i32* %"i"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.2", i32 %"i.2"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".11" = call i1 @"is_whitespace__1__char__ret_bool"(i8 %"ptr_load.1")
  br i1 %".11", label %"then", label %"else"
for.update:
  %"i.3" = load i32, i32* %"i"
  %".23" = add i32 %"i.3", 1
  store i32 %".23", i32* %"i"
  br label %"for.cond"
for.end:
  %"count.2" = load i32, i32* %"count"
  ret i32 %"count.2"
then:
  store i1 false, i1* %"in_word"
  br label %"ifcont"
else:
  %"in_word.1" = load i1, i1* %"in_word"
  %".15" = xor i1 %"in_word.1", -1
  br i1 %".15", label %"elif_then_0", label %"elif_else_0"
ifcont:
  br label %"for.update"
elif_then_0:
  store i1 true, i1* %"in_word"
  %"count.1" = load i32, i32* %"count"
  %".18" = add i32 %"count.1", 1
  store i32 %".18", i32* %"count"
  br label %"ifcont"
elif_else_0:
  br label %"ifcont"
}

define i8* @"replace_first__3__byte_ptr1__byte_ptr1__byte_ptr1__ret_byte"(i8* %"str", i8* %"find", i8* %"replace")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"find.addr" = alloca i8*
  store i8* %"find", i8** %"find.addr"
  %"replace.addr" = alloca i8*
  store i8* %"replace", i8** %"replace.addr"
  %"pos" = alloca i32
  %"str.1" = load i8*, i8** %"str.addr"
  %"find.1" = load i8*, i8** %"find.addr"
  %".8" = call i32 @"find_substring__3__byte_ptr1__byte_ptr1__int__ret_int"(i8* %"str.1", i8* %"find.1", i32 0)
  store i32 %".8", i32* %"pos"
  %"pos.1" = load i32, i32* %"pos"
  %".10" = sub i32 0, 1
  %".11" = icmp eq i32 %"pos.1", %".10"
  br i1 %".11", label %"then", label %"else"
then:
  %"str.2" = load i8*, i8** %"str.addr"
  %".13" = call i8* @"copy_string__1__byte_ptr1__ret_byte"(i8* %"str.2")
  ret i8* %".13"
else:
  br label %"ifcont"
ifcont:
  %"str_len" = alloca i32
  store i32 0, i32* %"str_len"
  br label %"while.cond"
while.cond:
  %"str.3" = load i8*, i8** %"str.addr"
  %"str_len.1" = load i32, i32* %"str_len"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.3", i32 %"str_len.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".18" = zext i8 %"ptr_load" to i32
  %".19" = icmp ne i32 %".18", 0
  br i1 %".19", label %"while.body", label %"while.end"
while.body:
  %"str_len.2" = load i32, i32* %"str_len"
  %".21" = add i32 %"str_len.2", 1
  store i32 %".21", i32* %"str_len"
  br label %"while.cond"
while.end:
  %"find_len" = alloca i32
  store i32 0, i32* %"find_len"
  br label %"while.cond.1"
while.cond.1:
  %"find.2" = load i8*, i8** %"find.addr"
  %"find_len.1" = load i32, i32* %"find_len"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"find.2", i32 %"find_len.1"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".26" = zext i8 %"ptr_load.1" to i32
  %".27" = icmp ne i32 %".26", 0
  br i1 %".27", label %"while.body.1", label %"while.end.1"
while.body.1:
  %"find_len.2" = load i32, i32* %"find_len"
  %".29" = add i32 %"find_len.2", 1
  store i32 %".29", i32* %"find_len"
  br label %"while.cond.1"
while.end.1:
  %"replace_len" = alloca i32
  store i32 0, i32* %"replace_len"
  br label %"while.cond.2"
while.cond.2:
  %"replace.1" = load i8*, i8** %"replace.addr"
  %"replace_len.1" = load i32, i32* %"replace_len"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"replace.1", i32 %"replace_len.1"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  %".34" = zext i8 %"ptr_load.2" to i32
  %".35" = icmp ne i32 %".34", 0
  br i1 %".35", label %"while.body.2", label %"while.end.2"
while.body.2:
  %"replace_len.2" = load i32, i32* %"replace_len"
  %".37" = add i32 %"replace_len.2", 1
  store i32 %".37", i32* %"replace_len"
  br label %"while.cond.2"
while.end.2:
  %"new_len" = alloca i32
  %"str_len.3" = load i32, i32* %"str_len"
  %"find_len.3" = load i32, i32* %"find_len"
  %".40" = sub i32 %"str_len.3", %"find_len.3"
  %"replace_len.3" = load i32, i32* %"replace_len"
  %".41" = add i32 %".40", %"replace_len.3"
  store i32 %".41", i32* %"new_len"
  %"result" = alloca i8*
  %"new_len.1" = load i32, i32* %"new_len"
  %".43" = zext i32 %"new_len.1" to i64
  %".44" = zext i32 1 to i64
  %".45" = add i64 %".43", %".44"
  %".46" = call i8* @"malloc"(i64 %".45")
  store i8* %".46", i8** %"result"
  %"result.1" = load i8*, i8** %"result"
  %".48" = ptrtoint i8* %"result.1" to i64
  %".49" = icmp eq i64 %".48", 0
  br i1 %".49", label %"then.1", label %"else.1"
then.1:
  %"int_to_ptr" = inttoptr i32 0 to i8*
  ret i8* %"int_to_ptr"
else.1:
  br label %"ifcont.1"
ifcont.1:
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"for.cond"
for.cond:
  %"i.1" = load i32, i32* %"i"
  %"pos.2" = load i32, i32* %"pos"
  %".55" = icmp slt i32 %"i.1", %"pos.2"
  br i1 %".55", label %"for.body", label %"for.end"
for.body:
  %"str.4" = load i8*, i8** %"str.addr"
  %"i.2" = load i32, i32* %"i"
  %"ptr_gep.3" = getelementptr inbounds i8, i8* %"str.4", i32 %"i.2"
  %"ptr_load.3" = load i8, i8* %"ptr_gep.3"
  %"result.2" = load i8*, i8** %"result"
  %"i.3" = load i32, i32* %"i"
  %".57" = getelementptr inbounds i8, i8* %"result.2", i32 %"i.3"
  %"str.5" = load i8*, i8** %"str.addr"
  %"i.4" = load i32, i32* %"i"
  %"ptr_gep.4" = getelementptr inbounds i8, i8* %"str.5", i32 %"i.4"
  %"ptr_load.4" = load i8, i8* %"ptr_gep.4"
  store i8 %"ptr_load.4", i8* %".57"
  br label %"for.update"
for.update:
  %"i.5" = load i32, i32* %"i"
  %".60" = add i32 %"i.5", 1
  store i32 %".60", i32* %"i"
  br label %"for.cond"
for.end:
  %"i.6" = alloca i32
  store i32 0, i32* %"i.6"
  br label %"for.cond.1"
for.cond.1:
  %"i.7" = load i32, i32* %"i.6"
  %"replace_len.4" = load i32, i32* %"replace_len"
  %".65" = icmp slt i32 %"i.7", %"replace_len.4"
  br i1 %".65", label %"for.body.1", label %"for.end.1"
for.body.1:
  %"replace.2" = load i8*, i8** %"replace.addr"
  %"i.8" = load i32, i32* %"i.6"
  %"ptr_gep.5" = getelementptr inbounds i8, i8* %"replace.2", i32 %"i.8"
  %"ptr_load.5" = load i8, i8* %"ptr_gep.5"
  %"result.3" = load i8*, i8** %"result"
  %"pos.3" = load i32, i32* %"pos"
  %"i.9" = load i32, i32* %"i.6"
  %".67" = add i32 %"pos.3", %"i.9"
  %".68" = getelementptr inbounds i8, i8* %"result.3", i32 %".67"
  %"replace.3" = load i8*, i8** %"replace.addr"
  %"i.10" = load i32, i32* %"i.6"
  %"ptr_gep.6" = getelementptr inbounds i8, i8* %"replace.3", i32 %"i.10"
  %"ptr_load.6" = load i8, i8* %"ptr_gep.6"
  store i8 %"ptr_load.6", i8* %".68"
  br label %"for.update.1"
for.update.1:
  %"i.11" = load i32, i32* %"i.6"
  %".71" = add i32 %"i.11", 1
  store i32 %".71", i32* %"i.6"
  br label %"for.cond.1"
for.end.1:
  %"i.12" = alloca i32
  %"pos.4" = load i32, i32* %"pos"
  %"find_len.4" = load i32, i32* %"find_len"
  %".74" = add i32 %"pos.4", %"find_len.4"
  store i32 %".74", i32* %"i.12"
  br label %"for.cond.2"
for.cond.2:
  %"i.13" = load i32, i32* %"i.12"
  %"str_len.4" = load i32, i32* %"str_len"
  %".77" = icmp sle i32 %"i.13", %"str_len.4"
  br i1 %".77", label %"for.body.2", label %"for.end.2"
for.body.2:
  %"str.6" = load i8*, i8** %"str.addr"
  %"i.14" = load i32, i32* %"i.12"
  %"ptr_gep.7" = getelementptr inbounds i8, i8* %"str.6", i32 %"i.14"
  %"ptr_load.7" = load i8, i8* %"ptr_gep.7"
  %"result.4" = load i8*, i8** %"result"
  %"i.15" = load i32, i32* %"i.12"
  %"find_len.5" = load i32, i32* %"find_len"
  %".79" = sub i32 %"i.15", %"find_len.5"
  %"replace_len.5" = load i32, i32* %"replace_len"
  %".80" = add i32 %".79", %"replace_len.5"
  %".81" = getelementptr inbounds i8, i8* %"result.4", i32 %".80"
  %"str.7" = load i8*, i8** %"str.addr"
  %"i.16" = load i32, i32* %"i.12"
  %"ptr_gep.8" = getelementptr inbounds i8, i8* %"str.7", i32 %"i.16"
  %"ptr_load.8" = load i8, i8* %"ptr_gep.8"
  store i8 %"ptr_load.8", i8* %".81"
  br label %"for.update.2"
for.update.2:
  %"i.17" = load i32, i32* %"i.12"
  %".84" = add i32 %"i.17", 1
  store i32 %".84", i32* %"i.12"
  br label %"for.cond.2"
for.end.2:
  %"result.5" = load i8*, i8** %"result"
  ret i8* %"result.5"
}

define i32 @"skip_until__3__byte_ptr1__int__char__ret_int"(i8* %"str", i32 %"pos", i8 %"ch")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"pos.addr" = alloca i32
  store i32 %"pos", i32* %"pos.addr"
  %"ch.addr" = alloca i8
  store i8 %"ch", i8* %"ch.addr"
  br label %"while.cond"
while.cond:
  %"str.1" = load i8*, i8** %"str.addr"
  %"pos.1" = load i32, i32* %"pos.addr"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %"pos.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".9" = zext i8 %"ptr_load" to i32
  %".10" = icmp ne i32 %".9", 0
  %"str.2" = load i8*, i8** %"str.addr"
  %"pos.2" = load i32, i32* %"pos.addr"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.2", i32 %"pos.2"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %"ch.1" = load i8, i8* %"ch.addr"
  %".11" = icmp ne i8 %"ptr_load.1", %"ch.1"
  %".12" = and i1 %".10", %".11"
  br i1 %".12", label %"while.body", label %"while.end"
while.body:
  %"pos.3" = load i32, i32* %"pos.addr"
  %".14" = add i32 %"pos.3", 1
  store i32 %".14", i32* %"pos.addr"
  br label %"while.cond"
while.end:
  %"pos.4" = load i32, i32* %"pos.addr"
  ret i32 %"pos.4"
}

define i32 @"skip_while_digit__2__byte_ptr1__int__ret_int"(i8* %"str", i32 %"pos")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"pos.addr" = alloca i32
  store i32 %"pos", i32* %"pos.addr"
  br label %"while.cond"
while.cond:
  %"str.1" = load i8*, i8** %"str.addr"
  %"pos.1" = load i32, i32* %"pos.addr"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %"pos.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".7" = zext i8 %"ptr_load" to i32
  %".8" = icmp ne i32 %".7", 0
  %"str.2" = load i8*, i8** %"str.addr"
  %"pos.2" = load i32, i32* %"pos.addr"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.2", i32 %"pos.2"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".9" = call i1 @"is_digit__1__char__ret_bool"(i8 %"ptr_load.1")
  %".10" = and i1 %".8", %".9"
  br i1 %".10", label %"while.body", label %"while.end"
while.body:
  %"pos.3" = load i32, i32* %"pos.addr"
  %".12" = add i32 %"pos.3", 1
  store i32 %".12", i32* %"pos.addr"
  br label %"while.cond"
while.end:
  %"pos.4" = load i32, i32* %"pos.addr"
  ret i32 %"pos.4"
}

define i32 @"skip_while_alnum__2__byte_ptr1__int__ret_int"(i8* %"str", i32 %"pos")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"pos.addr" = alloca i32
  store i32 %"pos", i32* %"pos.addr"
  br label %"while.cond"
while.cond:
  %"str.1" = load i8*, i8** %"str.addr"
  %"pos.1" = load i32, i32* %"pos.addr"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %"pos.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".7" = zext i8 %"ptr_load" to i32
  %".8" = icmp ne i32 %".7", 0
  %"str.2" = load i8*, i8** %"str.addr"
  %"pos.2" = load i32, i32* %"pos.addr"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.2", i32 %"pos.2"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".9" = call i1 @"is_alnum__1__char__ret_bool"(i8 %"ptr_load.1")
  %".10" = and i1 %".8", %".9"
  br i1 %".10", label %"while.body", label %"while.end"
while.body:
  %"pos.3" = load i32, i32* %"pos.addr"
  %".12" = add i32 %"pos.3", 1
  store i32 %".12", i32* %"pos.addr"
  br label %"while.cond"
while.end:
  %"pos.4" = load i32, i32* %"pos.addr"
  ret i32 %"pos.4"
}

define i32 @"skip_while_identifier__2__byte_ptr1__int__ret_int"(i8* %"str", i32 %"pos")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"pos.addr" = alloca i32
  store i32 %"pos", i32* %"pos.addr"
  br label %"while.cond"
while.cond:
  %"str.1" = load i8*, i8** %"str.addr"
  %"pos.1" = load i32, i32* %"pos.addr"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"str.1", i32 %"pos.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".7" = zext i8 %"ptr_load" to i32
  %".8" = icmp ne i32 %".7", 0
  %"str.2" = load i8*, i8** %"str.addr"
  %"pos.2" = load i32, i32* %"pos.addr"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.2", i32 %"pos.2"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %".9" = call i1 @"is_identifier_char__1__char__ret_bool"(i8 %"ptr_load.1")
  %".10" = and i1 %".8", %".9"
  br i1 %".10", label %"while.body", label %"while.end"
while.body:
  %"pos.3" = load i32, i32* %"pos.addr"
  %".12" = add i32 %"pos.3", 1
  store i32 %".12", i32* %"pos.addr"
  br label %"while.cond"
while.end:
  %"pos.4" = load i32, i32* %"pos.addr"
  ret i32 %"pos.4"
}

define i1 @"match_at__3__byte_ptr1__int__byte_ptr1__ret_bool"(i8* %"str", i32 %"pos", i8* %"pattern")
{
entry:
  %"str.addr" = alloca i8*
  store i8* %"str", i8** %"str.addr"
  %"pos.addr" = alloca i32
  store i32 %"pos", i32* %"pos.addr"
  %"pattern.addr" = alloca i8*
  store i8* %"pattern", i8** %"pattern.addr"
  %"i" = alloca i32
  store i32 0, i32* %"i"
  br label %"while.cond"
while.cond:
  %"pattern.1" = load i8*, i8** %"pattern.addr"
  %"i.1" = load i32, i32* %"i"
  %"ptr_gep" = getelementptr inbounds i8, i8* %"pattern.1", i32 %"i.1"
  %"ptr_load" = load i8, i8* %"ptr_gep"
  %".10" = zext i8 %"ptr_load" to i32
  %".11" = icmp ne i32 %".10", 0
  br i1 %".11", label %"while.body", label %"while.end"
while.body:
  %"str.1" = load i8*, i8** %"str.addr"
  %"pos.1" = load i32, i32* %"pos.addr"
  %"i.2" = load i32, i32* %"i"
  %".13" = add i32 %"pos.1", %"i.2"
  %"ptr_gep.1" = getelementptr inbounds i8, i8* %"str.1", i32 %".13"
  %"ptr_load.1" = load i8, i8* %"ptr_gep.1"
  %"pattern.2" = load i8*, i8** %"pattern.addr"
  %"i.3" = load i32, i32* %"i"
  %"ptr_gep.2" = getelementptr inbounds i8, i8* %"pattern.2", i32 %"i.3"
  %"ptr_load.2" = load i8, i8* %"ptr_gep.2"
  %".14" = icmp ne i8 %"ptr_load.1", %"ptr_load.2"
  br i1 %".14", label %"then", label %"else"
while.end:
  ret i1 true
then:
  ret i1 false
else:
  br label %"ifcont"
ifcont:
  %"i.4" = load i32, i32* %"i"
  %".18" = add i32 %"i.4", 1
  store i32 %".18", i32* %"i"
  br label %"while.cond"
}

define %"string"* @"string.__init"(%"string"* %"this", i8* %"x")
{
entry:
  %"x.addr" = alloca i8*
  store i8* %"x", i8** %"x.addr"
  %"x.1" = load i8*, i8** %"x.addr"
  %".5" = getelementptr inbounds %"string", %"string"* %"this", i1 0, i32 0
  store i8* %"x.1", i8** %".5"
  ret %"string"* %"this"
}

define void @"string.__exit"(%"string"* %"this")
{
entry:
  ret void
}

define i8* @"string.val"(%"string"* %"this")
{
entry:
  %"struct_load" = load %"string", %"string"* %"this"
  %"value_ptr" = getelementptr %"string", %"string"* %"this", i32 0, i32 0
  %"value" = load i8*, i8** %"value_ptr"
  ret i8* %"value"
}

define i32 @"string.len"(%"string"* %"this")
{
entry:
  %"struct_load" = load %"string", %"string"* %"this"
  %"value_ptr" = getelementptr %"string", %"string"* %"this", i32 0, i32 0
  %"value" = load i8*, i8** %"value_ptr"
  %".3" = call i64 @"strlen"(i8* %"value")
  %".4" = trunc i64 %".3" to i32
  ret i32 %".4"
}

define i1 @"string.set"(%"string"* %"this", i8* %"s")
{
entry:
  %"s.addr" = alloca i8*
  store i8* %"s", i8** %"s.addr"
  %"exception_flag" = alloca i1
  %"exception_value" = alloca i64
  store i1 0, i1* %"exception_flag"
  br label %"try.body"
try.body:
  %"s.1" = load i8*, i8** %"s.addr"
  %".7" = getelementptr inbounds %"string", %"string"* %"this", i1 0, i32 0
  store i8* %"s.1", i8** %".7"
  ret i1 true
catch.check:
  %"exc_flag" = load i1, i1* %"exception_flag"
  %"has_exception" = icmp ne i1 %"exc_flag", 0
  br i1 %"has_exception", label %"catch.0", label %"try.end"
try.end:
  ret i1 false
catch.0:
  store i1 0, i1* %"exception_flag"
  ret i1 false
}

declare external i8* @"fopen"(i8* %"filename", i8* %"mode")

declare external i32 @"fclose"(i8* %"stream")

declare external i32 @"fread"(i8* %"ptr", i32 %"size", i32 %"count", i8* %"stream")

declare external i32 @"fwrite"(i8* %"ptr", i32 %"size", i32 %"count", i8* %"stream")

declare external i32 @"fseek"(i8* %"stream", i32 %"offset", i32 %"whence")

declare external i32 @"ftell"(i8* %"stream")

declare external void @"rewind"(i8* %"stream")

declare external i32 @"feof"(i8* %"stream")

declare external i32 @"ferror"(i8* %"stream")

@"standard__io__file__SEEK_SET" = internal global i32 0
@"standard__io__file__SEEK_CUR" = internal global i32 1
@"standard__io__file__SEEK_END" = internal global i32 2
define i32 @"standard__io__file__read_file__3__byte_ptr1__byte_arr__int__ret_int"(i8* %"filename", i8* %"buffer", i32 %"buffer_size")
{
entry:
  %"filename.addr" = alloca i8*
  store i8* %"filename", i8** %"filename.addr"
  %"buffer.addr" = alloca i8*
  store i8* %"buffer", i8** %"buffer.addr"
  %"buffer_size.addr" = alloca i32
  store i32 %"buffer_size", i32* %"buffer_size.addr"
  %"file" = alloca i8*
  %"filename.1" = load i8*, i8** %"filename.addr"
  %"str_stack" = alloca [3 x i8]
  %"str_char_0" = getelementptr [3 x i8], [3 x i8]* %"str_stack", i32 0, i32 0
  store i8 114, i8* %"str_char_0"
  %"str_char_1" = getelementptr [3 x i8], [3 x i8]* %"str_stack", i32 0, i32 1
  store i8 98, i8* %"str_char_1"
  %"str_char_2" = getelementptr [3 x i8], [3 x i8]* %"str_stack", i32 0, i32 2
  store i8 0, i8* %"str_char_2"
  %"arg1_to_void_ptr" = bitcast [3 x i8]* %"str_stack" to i8*
  %".11" = call i8* @"fopen"(i8* %"filename.1", i8* %"arg1_to_void_ptr")
  store i8* %".11", i8** %"file"
  %"file.1" = load i8*, i8** %"file"
  %".13" = ptrtoint i8* %"file.1" to i64
  %".14" = icmp eq i64 %".13", 0
  br i1 %".14", label %"then", label %"else"
then:
  %".16" = sub i32 0, 1
  ret i32 %".16"
else:
  br label %"ifcont"
ifcont:
  %"file.2" = load i8*, i8** %"file"
  %".19" = call i32 @"fseek"(i8* %"file.2", i32 0, i32 2)
  %"file_size" = alloca i32
  %"file.3" = load i8*, i8** %"file"
  %".20" = call i32 @"ftell"(i8* %"file.3")
  store i32 %".20", i32* %"file_size"
  %"file.4" = load i8*, i8** %"file"
  call void @"rewind"(i8* %"file.4")
  %"bytes_to_read" = alloca i32
  %"file_size.1" = load i32, i32* %"file_size"
  store i32 %"file_size.1", i32* %"bytes_to_read"
  %"bytes_to_read.1" = load i32, i32* %"bytes_to_read"
  %"buffer_size.1" = load i32, i32* %"buffer_size.addr"
  %".24" = icmp sgt i32 %"bytes_to_read.1", %"buffer_size.1"
  br i1 %".24", label %"then.1", label %"else.1"
then.1:
  %"buffer_size.2" = load i32, i32* %"buffer_size.addr"
  store i32 %"buffer_size.2", i32* %"bytes_to_read"
  br label %"ifcont.1"
else.1:
  br label %"ifcont.1"
ifcont.1:
  %"bytes_read" = alloca i32
  %"buffer.1" = load i8*, i8** %"buffer.addr"
  %"bytes_to_read.2" = load i32, i32* %"bytes_to_read"
  %"file.5" = load i8*, i8** %"file"
  %".29" = call i32 @"fread"(i8* %"buffer.1", i32 1, i32 %"bytes_to_read.2", i8* %"file.5")
  store i32 %".29", i32* %"bytes_read"
  %"file.6" = load i8*, i8** %"file"
  %".31" = call i32 @"fclose"(i8* %"file.6")
  %"bytes_read.1" = load i32, i32* %"bytes_read"
  ret i32 %"bytes_read.1"
}

define i32 @"standard__io__file__write_file__3__byte_ptr1__byte_arr__int__ret_int"(i8* %"filename", i8* %"xd", i32 %"data_size")
{
entry:
  %"filename.addr" = alloca i8*
  store i8* %"filename", i8** %"filename.addr"
  %"xd.addr" = alloca i8*
  store i8* %"xd", i8** %"xd.addr"
  %"data_size.addr" = alloca i32
  store i32 %"data_size", i32* %"data_size.addr"
  %"file" = alloca i8*
  %"filename.1" = load i8*, i8** %"filename.addr"
  %"str_stack" = alloca [3 x i8]
  %"str_char_0" = getelementptr [3 x i8], [3 x i8]* %"str_stack", i32 0, i32 0
  store i8 119, i8* %"str_char_0"
  %"str_char_1" = getelementptr [3 x i8], [3 x i8]* %"str_stack", i32 0, i32 1
  store i8 98, i8* %"str_char_1"
  %"str_char_2" = getelementptr [3 x i8], [3 x i8]* %"str_stack", i32 0, i32 2
  store i8 0, i8* %"str_char_2"
  %"arg1_to_void_ptr" = bitcast [3 x i8]* %"str_stack" to i8*
  %".11" = call i8* @"fopen"(i8* %"filename.1", i8* %"arg1_to_void_ptr")
  store i8* %".11", i8** %"file"
  %"file.1" = load i8*, i8** %"file"
  %".13" = ptrtoint i8* %"file.1" to i64
  %".14" = icmp eq i64 %".13", 0
  br i1 %".14", label %"then", label %"else"
then:
  %".16" = sub i32 0, 1
  ret i32 %".16"
else:
  br label %"ifcont"
ifcont:
  %"bytes_written" = alloca i32
  %"xd.1" = load i8*, i8** %"xd.addr"
  %"data_size.1" = load i32, i32* %"data_size.addr"
  %"file.2" = load i8*, i8** %"file"
  %".19" = call i32 @"fwrite"(i8* %"xd.1", i32 1, i32 %"data_size.1", i8* %"file.2")
  store i32 %".19", i32* %"bytes_written"
  %"file.3" = load i8*, i8** %"file"
  %".21" = call i32 @"fclose"(i8* %"file.3")
  %"bytes_written.1" = load i32, i32* %"bytes_written"
  ret i32 %"bytes_written.1"
}

define i32 @"standard__io__file__append_file__3__byte_ptr1__byte_arr__int__ret_int"(i8* %"filename", i8* %"xd", i32 %"data_size")
{
entry:
  %"filename.addr" = alloca i8*
  store i8* %"filename", i8** %"filename.addr"
  %"xd.addr" = alloca i8*
  store i8* %"xd", i8** %"xd.addr"
  %"data_size.addr" = alloca i32
  store i32 %"data_size", i32* %"data_size.addr"
  %"file" = alloca i8*
  %"filename.1" = load i8*, i8** %"filename.addr"
  %"str_stack" = alloca [3 x i8]
  %"str_char_0" = getelementptr [3 x i8], [3 x i8]* %"str_stack", i32 0, i32 0
  store i8 97, i8* %"str_char_0"
  %"str_char_1" = getelementptr [3 x i8], [3 x i8]* %"str_stack", i32 0, i32 1
  store i8 98, i8* %"str_char_1"
  %"str_char_2" = getelementptr [3 x i8], [3 x i8]* %"str_stack", i32 0, i32 2
  store i8 0, i8* %"str_char_2"
  %"arg1_to_void_ptr" = bitcast [3 x i8]* %"str_stack" to i8*
  %".11" = call i8* @"fopen"(i8* %"filename.1", i8* %"arg1_to_void_ptr")
  store i8* %".11", i8** %"file"
  %"file.1" = load i8*, i8** %"file"
  %".13" = ptrtoint i8* %"file.1" to i64
  %".14" = icmp eq i64 %".13", 0
  br i1 %".14", label %"then", label %"else"
then:
  %".16" = sub i32 0, 1
  ret i32 %".16"
else:
  br label %"ifcont"
ifcont:
  %"bytes_written" = alloca i32
  %"xd.1" = load i8*, i8** %"xd.addr"
  %"data_size.1" = load i32, i32* %"data_size.addr"
  %"file.2" = load i8*, i8** %"file"
  %".19" = call i32 @"fwrite"(i8* %"xd.1", i32 1, i32 %"data_size.1", i8* %"file.2")
  store i32 %".19", i32* %"bytes_written"
  %"file.3" = load i8*, i8** %"file"
  %".21" = call i32 @"fclose"(i8* %"file.3")
  %"bytes_written.1" = load i32, i32* %"bytes_written"
  ret i32 %"bytes_written.1"
}

define i32 @"standard__io__file__get_file_size__1__byte_ptr1__ret_int"(i8* %"filename")
{
entry:
  %"filename.addr" = alloca i8*
  store i8* %"filename", i8** %"filename.addr"
  %"file" = alloca i8*
  %"filename.1" = load i8*, i8** %"filename.addr"
  %"str_stack" = alloca [3 x i8]
  %"str_char_0" = getelementptr [3 x i8], [3 x i8]* %"str_stack", i32 0, i32 0
  store i8 114, i8* %"str_char_0"
  %"str_char_1" = getelementptr [3 x i8], [3 x i8]* %"str_stack", i32 0, i32 1
  store i8 98, i8* %"str_char_1"
  %"str_char_2" = getelementptr [3 x i8], [3 x i8]* %"str_stack", i32 0, i32 2
  store i8 0, i8* %"str_char_2"
  %"arg1_to_void_ptr" = bitcast [3 x i8]* %"str_stack" to i8*
  %".7" = call i8* @"fopen"(i8* %"filename.1", i8* %"arg1_to_void_ptr")
  store i8* %".7", i8** %"file"
  %"file.1" = load i8*, i8** %"file"
  %".9" = ptrtoint i8* %"file.1" to i64
  %".10" = icmp eq i64 %".9", 0
  br i1 %".10", label %"then", label %"else"
then:
  %".12" = sub i32 0, 1
  ret i32 %".12"
else:
  br label %"ifcont"
ifcont:
  %"file.2" = load i8*, i8** %"file"
  %".15" = call i32 @"fseek"(i8* %"file.2", i32 0, i32 2)
  %"size" = alloca i32
  %"file.3" = load i8*, i8** %"file"
  %".16" = call i32 @"ftell"(i8* %"file.3")
  store i32 %".16", i32* %"size"
  %"file.4" = load i8*, i8** %"file"
  %".18" = call i32 @"fclose"(i8* %"file.4")
  %"size.1" = load i32, i32* %"size"
  ret i32 %"size.1"
}

define i1 @"standard__io__file__file_exists__1__byte_ptr1__ret_bool"(i8* %"filename")
{
entry:
  %"filename.addr" = alloca i8*
  store i8* %"filename", i8** %"filename.addr"
  %"file" = alloca i8*
  %"filename.1" = load i8*, i8** %"filename.addr"
  %"str_stack" = alloca [3 x i8]
  %"str_char_0" = getelementptr [3 x i8], [3 x i8]* %"str_stack", i32 0, i32 0
  store i8 114, i8* %"str_char_0"
  %"str_char_1" = getelementptr [3 x i8], [3 x i8]* %"str_stack", i32 0, i32 1
  store i8 98, i8* %"str_char_1"
  %"str_char_2" = getelementptr [3 x i8], [3 x i8]* %"str_stack", i32 0, i32 2
  store i8 0, i8* %"str_char_2"
  %"arg1_to_void_ptr" = bitcast [3 x i8]* %"str_stack" to i8*
  %".7" = call i8* @"fopen"(i8* %"filename.1", i8* %"arg1_to_void_ptr")
  store i8* %".7", i8** %"file"
  %"file.1" = load i8*, i8** %"file"
  %".9" = ptrtoint i8* %"file.1" to i64
  %".10" = icmp eq i64 %".9", 0
  br i1 %".10", label %"then", label %"else"
then:
  %".12" = trunc i32 0 to i1
  ret i1 %".12"
else:
  br label %"ifcont"
ifcont:
  %"file.2" = load i8*, i8** %"file"
  %".15" = call i32 @"fclose"(i8* %"file.2")
  %".16" = trunc i32 1 to i1
  ret i1 %".16"
}

@"OS_UNKNOWN" = internal global i32 0
@"OS_WINDOWS" = internal global i32 1
@"OS_LINUX" = internal global i32 2
@"OS_MACOS" = internal global i32 3
define i32 @"standard__io__console__win_input__2__byte_arr__int__ret_int"(i8* %"buf", i32 %"max_len")
{
entry:
  %"buf.addr" = alloca i8*
  store i8* %"buf", i8** %"buf.addr"
  %"max_len.addr" = alloca i32
  store i32 %"max_len", i32* %"max_len.addr"
  %"bytes_read" = alloca i32
  store i32 0, i32* %"bytes_read"
  %"bytes_read_ptr" = alloca i32*
  store i32* %"bytes_read", i32** %"bytes_read_ptr"
  %"original_mode" = alloca i32
  store i32 0, i32* %"original_mode"
  %"mode_ptr" = alloca i32*
  store i32* %"original_mode", i32** %"mode_ptr"
  %"buf_load" = load i8*, i8** %"buf.addr"
  %"max_len_load" = load i32, i32* %"max_len.addr"
  %"bytes_read_ptr_load" = load i32*, i32** %"bytes_read_ptr"
  %"mode_ptr_load" = load i32*, i32** %"mode_ptr"
  call void asm sideeffect "movq $$-10, %rcx
                    subq $$32, %rsp
                    call GetStdHandle
                    addq $$32, %rsp
                    movq %rax, %r12
                    movq %rax, %rcx
                    movq $3, %rdx
                    subq $$32, %rsp
                    call GetConsoleMode
                    addq $$32, %rsp
                    movq %r12, %rcx
                    movq $$0x001F, %rdx
                    subq $$32, %rsp
                    call SetConsoleMode
                    addq $$32, %rsp
                    movq %r12, %rcx
                    movq $0, %rdx           
                    movl $1, %r8d           
                    movq $2, %r9            
                    subq $$40, %rsp
                    movq $$0, 32(%rsp)
                    call ReadFile
                    addq $$40, %rsp
                    movq %r12, %rcx
                    movl ($3), %edx
                    subq $$32, %rsp
                    call SetConsoleMode
                    addq $$32, %rsp
                    movl ($2), %eax", "r,r,r,r,~{rax},~{rcx},~{rdx},~{r8},~{r9},~{r10},~{r11},~{r12},~{memory}"
(i8* %"buf_load", i32 %"max_len_load", i32* %"bytes_read_ptr_load", i32* %"mode_ptr_load")
  call void @"standard__io__console__reset_from_input__0__ret_void"()
  %"bytes_read.1" = load i32, i32* %"bytes_read"
  %".12" = sub i32 %"bytes_read.1", 2
  ret i32 %".12"
}

define i32 @"standard__io__console__input__2__byte_arr__int__ret_int"(i8* %"buffer", i32 %"max_len")
{
entry:
  %"buffer.addr" = alloca i8*
  store i8* %"buffer", i8** %"buffer.addr"
  %"max_len.addr" = alloca i32
  store i32 %"max_len", i32* %"max_len.addr"
  switch i32 1, label %"switch_default" [i32 1, label %"switch_case_0"]
switch_merge:
  ret i32 0
switch_case_0:
  %"buffer.1" = load i8*, i8** %"buffer.addr"
  %"max_len.1" = load i32, i32* %"max_len.addr"
  %".7" = call i32 @"standard__io__console__win_input__2__byte_arr__int__ret_int"(i8* %"buffer.1", i32 %"max_len.1")
  ret i32 %".7"
switch_default:
  ret i32 0
}

define void @"standard__io__console__win_print__2__byte_ptr1__int__ret_void"(i8* %"msg", i32 %"x")
{
entry:
  %"msg.addr" = alloca i8*
  store i8* %"msg", i8** %"msg.addr"
  %"x.addr" = alloca i32
  store i32 %"x", i32* %"x.addr"
  %"msg_load" = load i8*, i8** %"msg.addr"
  %"x_load" = load i32, i32* %"x.addr"
  call void asm sideeffect "movq $$-11, %rcx
                    subq $$32, %rsp
                    call GetStdHandle
                    addq $$32, %rsp
                    movq %rax, %rcx         
                    movq $0, %rdx           
                    movl $1, %r8d           
                    xorq %r9, %r9           
                    subq $$40, %rsp         
                    movq %r9, 32(%rsp)      
                    call WriteFile
                    addq $$40, %rsp", "r,r,~{rax},~{rcx},~{rdx},~{r8},~{r9},~{r10},~{r11},~{memory}"
(i8* %"msg_load", i32 %"x_load")
  ret void
}

define void @"standard__io__console__print__2__noopstr__int__ret_void"(i8* %"s", i32 %"len")
{
entry:
  %"s.addr" = alloca i8*
  store i8* %"s", i8** %"s.addr"
  %"len.addr" = alloca i32
  store i32 %"len", i32* %"len.addr"
  switch i32 1, label %"switch_default" [i32 1, label %"switch_case_0"]
switch_merge:
  %"s_void_ptr" = bitcast i8** %"s.addr" to i8*
  call void asm sideeffect "
                movq %rcx, %r10
                movl $$0x1E, %eax
                syscall
            ", "r,~{rax},~{r10},~{r11},~{memory}"
(i8* %"s_void_ptr")
  ret void
switch_case_0:
  %"s_ptr" = load i8*, i8** %"s.addr"
  %"len.1" = load i32, i32* %"len.addr"
  call void @"standard__io__console__win_print__2__byte_ptr1__int__ret_void"(i8* %"s_ptr", i32 %"len.1")
  br label %"switch_merge"
switch_default:
  ret void
}

define void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"s")
{
entry:
  %"s.addr" = alloca i8*
  store i8* %"s", i8** %"s.addr"
  %"len" = alloca i32
  %"s_ptr" = load i8*, i8** %"s.addr"
  %".4" = call i64 @"strlen"(i8* %"s_ptr")
  %".5" = trunc i64 %".4" to i32
  store i32 %".5", i32* %"len"
  switch i32 1, label %"switch_default" [i32 1, label %"switch_case_0"]
switch_merge:
  %"s_void_ptr" = bitcast i8** %"s.addr" to i8*
  call void asm sideeffect "
                movq %rcx, %r10
                movl $$0x1E, %eax
                syscall
            ", "r,~{rax},~{r10},~{r11},~{memory}"
(i8* %"s_void_ptr")
  ret void
switch_case_0:
  %"s_ptr.1" = load i8*, i8** %"s.addr"
  %"len.1" = load i32, i32* %"len"
  call void @"standard__io__console__win_print__2__byte_ptr1__int__ret_void"(i8* %"s_ptr.1", i32 %"len.1")
  br label %"switch_merge"
switch_default:
  ret void
}

define void @"standard__io__console__print__1__byte__ret_void"(i8 %"s")
{
entry:
  %"s.addr" = alloca i8
  store i8 %"s", i8* %"s.addr"
  %"x" = alloca [2 x i8]
  %"elem_0" = getelementptr inbounds [2 x i8], [2 x i8]* %"x", i32 0, i32 0
  %"s.1" = load i8, i8* %"s.addr"
  store i8 %"s.1", i8* %"elem_0"
  %"elem_1" = getelementptr inbounds [2 x i8], [2 x i8]* %"x", i32 0, i32 1
  %".5" = trunc i32 0 to i8
  store i8 %".5", i8* %"elem_1"
  %"arg0_to_void_ptr" = bitcast [2 x i8]* %"x" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr")
  ret void
}

define void @"standard__io__console__reset_from_input__0__ret_void"()
{
entry:
  %"bs" = alloca i8
  %".2" = trunc i32 8 to i8
  store i8 %".2", i8* %"bs"
  call void @"standard__io__console__win_print__2__byte_ptr1__int__ret_void"(i8* %"bs", i32 1)
  call void @"standard__io__console__win_print__2__byte_ptr1__int__ret_void"(i8* %"bs", i32 1)
  ret void
}

declare void @"standard__io__console__printchar__1__noopstr__ret_void"(i8* %".1")

declare void @"standard__io__console__print__1__i8__ret_void"(i8 %".1")

declare void @"standard__io__console__print__1__i16__ret_void"(i16 %".1")

define void @"standard__io__console__print__1__int__ret_void"(i32 %"x")
{
entry:
  %"x.addr" = alloca i32
  store i32 %"x", i32* %"x.addr"
  %"buf" = alloca [21 x i8]
  %"x.1" = load i32, i32* %"x.addr"
  %"arg1_to_void_ptr" = bitcast [21 x i8]* %"buf" to i8*
  %".4" = call i32 @"i32str__2__i32__byte_ptr1__ret_i32"(i32 %"x.1", i8* %"arg1_to_void_ptr")
  %"arg0_to_void_ptr" = bitcast [21 x i8]* %"buf" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr")
  ret void
}

define void @"standard__io__console__print__1__i64__ret_void"(i64 %"x")
{
entry:
  %"x.addr" = alloca i64
  store i64 %"x", i64* %"x.addr"
  %"buf" = alloca [21 x i8]
  %"x.1" = load i64, i64* %"x.addr"
  %"arg1_to_void_ptr" = bitcast [21 x i8]* %"buf" to i8*
  %".4" = call i64 @"i64str__2__i64__byte_ptr1__ret_i64"(i64 %"x.1", i8* %"arg1_to_void_ptr")
  %"arg0_to_void_ptr" = bitcast [21 x i8]* %"buf" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr")
  ret void
}

declare void @"standard__io__console__print__1__u16__ret_void"(i16 %".1")

define void @"standard__io__console__print__1__uint__ret_void"(i32 %"x")
{
entry:
  %"x.addr" = alloca i32
  store i32 %"x", i32* %"x.addr"
  %"buf" = alloca [21 x i8]
  %"x.1" = load i32, i32* %"x.addr"
  %"arg1_to_void_ptr" = bitcast [21 x i8]* %"buf" to i8*
  %".4" = call i32 @"u32str__2__u32__byte_ptr1__ret_u32"(i32 %"x.1", i8* %"arg1_to_void_ptr")
  %"arg0_to_void_ptr" = bitcast [21 x i8]* %"buf" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr")
  ret void
}

define void @"standard__io__console__print__1__u64__ret_void"(i64 %"x")
{
entry:
  %"x.addr" = alloca i64
  store i64 %"x", i64* %"x.addr"
  %"buf" = alloca [21 x i8]
  %"x.1" = load i64, i64* %"x.addr"
  %"arg1_to_void_ptr" = bitcast [21 x i8]* %"buf" to i8*
  %".4" = call i64 @"u64str__2__u64__byte_ptr1__ret_u64"(i64 %"x.1", i8* %"arg1_to_void_ptr")
  %"arg0_to_void_ptr" = bitcast [21 x i8]* %"buf" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr")
  ret void
}

define void @"standard__io__console__print__1__float__ret_void"(float %"x")
{
entry:
  %"x.addr" = alloca float
  store float %"x", float* %"x.addr"
  %"buffer" = alloca [256 x i8]
  %"x.1" = load float, float* %"x.addr"
  %"arg1_to_void_ptr" = bitcast [256 x i8]* %"buffer" to i8*
  %".4" = call i32 @"float2str__3__float__byte_ptr1__i32__ret_i32"(float %"x.1", i8* %"arg1_to_void_ptr", i32 5)
  %"arg0_to_void_ptr" = bitcast [256 x i8]* %"buffer" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr")
  ret void
}

define void @"standard__io__console__print__2__float__int__ret_void"(float %"x", i32 %"y")
{
entry:
  %"x.addr" = alloca float
  store float %"x", float* %"x.addr"
  %"y.addr" = alloca i32
  store i32 %"y", i32* %"y.addr"
  %"buffer" = alloca [256 x i8]
  %"x.1" = load float, float* %"x.addr"
  %"arg1_to_void_ptr" = bitcast [256 x i8]* %"buffer" to i8*
  %"y.1" = load i32, i32* %"y.addr"
  %".6" = call i32 @"float2str__3__float__byte_ptr1__i32__ret_i32"(float %"x.1", i8* %"arg1_to_void_ptr", i32 %"y.1")
  %"arg0_to_void_ptr" = bitcast [256 x i8]* %"buffer" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr")
  ret void
}

define void @"standard__io__console__print__0__ret_void"()
{
entry:
  switch i32 1, label %"switch_default" [i32 1, label %"switch_case_0"]
switch_merge:
  ret void
switch_case_0:
  %"str_stack" = alloca [1 x i8]
  %"str_char_0" = getelementptr [1 x i8], [1 x i8]* %"str_stack", i32 0, i32 0
  store i8 10, i8* %"str_char_0"
  %"arg0_to_void_ptr" = bitcast [1 x i8]* %"str_stack" to i8*
  call void @"standard__io__console__win_print__2__byte_ptr1__int__ret_void"(i8* %"arg0_to_void_ptr", i32 1)
  br label %"switch_merge"
switch_default:
  ret void
}

define i64 @"standard__io__file__win_open__5__byte_ptr1__u32__u32__u32__u32__ret_i64"(i8* %"path", i32 %"access", i32 %"share", i32 %"disposition", i32 %"attributes")
{
entry:
  %"path.addr" = alloca i8*
  store i8* %"path", i8** %"path.addr"
  %"access.addr" = alloca i32
  store i32 %"access", i32* %"access.addr"
  %"share.addr" = alloca i32
  store i32 %"share", i32* %"share.addr"
  %"disposition.addr" = alloca i32
  store i32 %"disposition", i32* %"disposition.addr"
  %"attributes.addr" = alloca i32
  store i32 %"attributes", i32* %"attributes.addr"
  %"handle" = alloca i64
  %".12" = sub i32 0, 1
  %".13" = sext i32 %".12" to i64
  store i64 %".13", i64* %"handle"
  %"path_load" = load i8*, i8** %"path.addr"
  %"access_load" = load i32, i32* %"access.addr"
  %"share_load" = load i32, i32* %"share.addr"
  %"disposition_load" = load i32, i32* %"disposition.addr"
  %"attributes_load" = load i32, i32* %"attributes.addr"
  call void asm sideeffect "movq $0, %rcx           
                    movl $1, %edx           
                    movl $2, %r8d           
                    xorq %r9, %r9           
                    subq $$56, %rsp
                    movl $3, %eax           
                    movl %eax, 32(%rsp)     
                    movl $4, %eax           
                    movl %eax, 40(%rsp)     
                    xorq %rax, %rax
                    movq %rax, 48(%rsp)     
                    call CreateFileA
                    movq %rax, $5           
                    addq $$56, %rsp", "r,r,r,r,r,m,~{rax},~{rcx},~{rdx},~{r8},~{r9},~{r10},~{r11},~{memory}"
(i8* %"path_load", i32 %"access_load", i32 %"share_load", i32 %"disposition_load", i32 %"attributes_load", i64* %"handle")
  %"handle.1" = load i64, i64* %"handle"
  ret i64 %"handle.1"
}

define i32 @"standard__io__file__win_read__3__i64__byte_ptr1__u32__ret_i32"(i64 %"handle", i8* %"buffer", i32 %"bytes_to_read")
{
entry:
  %"handle.addr" = alloca i64
  store i64 %"handle", i64* %"handle.addr"
  %"buffer.addr" = alloca i8*
  store i8* %"buffer", i8** %"buffer.addr"
  %"bytes_to_read.addr" = alloca i32
  store i32 %"bytes_to_read", i32* %"bytes_to_read.addr"
  %"bytes_read" = alloca i32
  store i32 0, i32* %"bytes_read"
  %"bytes_read_ptr" = alloca i32*
  store i32* %"bytes_read", i32** %"bytes_read_ptr"
  %"success" = alloca i32
  store i32 0, i32* %"success"
  %"handle_load" = load i64, i64* %"handle.addr"
  %"buffer_load" = load i8*, i8** %"buffer.addr"
  %"bytes_to_read_load" = load i32, i32* %"bytes_to_read.addr"
  %"bytes_read_ptr_load" = load i32*, i32** %"bytes_read_ptr"
  call void asm sideeffect "movq $0, %rcx           
                    movq $1, %rdx           
                    movl $2, %r8d           
                    movq $3, %r9            
                    subq $$40, %rsp
                    xorq %rax, %rax
                    movq %rax, 32(%rsp)     
                    call ReadFile
                    movl %eax, $4           
                    addq $$40, %rsp", "r,r,r,r,m,~{rax},~{rcx},~{rdx},~{r8},~{r9},~{r10},~{r11},~{memory}"
(i64 %"handle_load", i8* %"buffer_load", i32 %"bytes_to_read_load", i32* %"bytes_read_ptr_load", i32* %"success")
  %"success.1" = load i32, i32* %"success"
  %".12" = icmp eq i32 %"success.1", 0
  br i1 %".12", label %"then", label %"else"
then:
  %".14" = sub i32 0, 1
  ret i32 %".14"
else:
  br label %"ifcont"
ifcont:
  %"bytes_read.1" = load i32, i32* %"bytes_read"
  ret i32 %"bytes_read.1"
}

define i32 @"standard__io__file__win_write__3__i64__byte_ptr1__u32__ret_i32"(i64 %"handle", i8* %"buffer", i32 %"bytes_to_write")
{
entry:
  %"handle.addr" = alloca i64
  store i64 %"handle", i64* %"handle.addr"
  %"buffer.addr" = alloca i8*
  store i8* %"buffer", i8** %"buffer.addr"
  %"bytes_to_write.addr" = alloca i32
  store i32 %"bytes_to_write", i32* %"bytes_to_write.addr"
  %"bytes_written" = alloca i32
  store i32 0, i32* %"bytes_written"
  %"bytes_written_ptr" = alloca i32*
  store i32* %"bytes_written", i32** %"bytes_written_ptr"
  %"success" = alloca i32
  store i32 0, i32* %"success"
  %"handle_load" = load i64, i64* %"handle.addr"
  %"buffer_load" = load i8*, i8** %"buffer.addr"
  %"bytes_to_write_load" = load i32, i32* %"bytes_to_write.addr"
  %"bytes_written_ptr_load" = load i32*, i32** %"bytes_written_ptr"
  call void asm sideeffect "movq $0, %rcx           
                    movq $1, %rdx           
                    movl $2, %r8d           
                    movq $3, %r9            
                    subq $$40, %rsp
                    xorq %rax, %rax
                    movq %rax, 32(%rsp)     
                    call WriteFile
                    movl %eax, $4           
                    addq $$40, %rsp", "r,r,r,r,m,~{rax},~{rcx},~{rdx},~{r8},~{r9},~{r10},~{r11},~{memory}"
(i64 %"handle_load", i8* %"buffer_load", i32 %"bytes_to_write_load", i32* %"bytes_written_ptr_load", i32* %"success")
  %"success.1" = load i32, i32* %"success"
  %".12" = icmp eq i32 %"success.1", 0
  br i1 %".12", label %"then", label %"else"
then:
  %".14" = sub i32 0, 1
  ret i32 %".14"
else:
  br label %"ifcont"
ifcont:
  %"bytes_written.1" = load i32, i32* %"bytes_written"
  ret i32 %"bytes_written.1"
}

define i32 @"standard__io__file__win_close__1__i64__ret_i32"(i64 %"handle")
{
entry:
  %"handle.addr" = alloca i64
  store i64 %"handle", i64* %"handle.addr"
  %"result" = alloca i32
  store i32 0, i32* %"result"
  %"handle_load" = load i64, i64* %"handle.addr"
  call void asm sideeffect "movq $0, %rcx           
                    subq $$32, %rsp
                    call CloseHandle
                    movl %eax, $1           
                    addq $$32, %rsp", "r,m,~{rax},~{rcx},~{rdx},~{r8},~{r9},~{r10},~{r11},~{memory}"
(i64 %"handle_load", i32* %"result")
  %"result.1" = load i32, i32* %"result"
  ret i32 %"result.1"
}

define i64 @"standard__io__file__open_read__1__byte_ptr1__ret_i64"(i8* %"path")
{
entry:
  %"path.addr" = alloca i8*
  store i8* %"path", i8** %"path.addr"
  %"path.1" = load i8*, i8** %"path.addr"
  %".4" = trunc i64 2147483648 to i32
  %".5" = call i64 @"standard__io__file__win_open__5__byte_ptr1__u32__u32__u32__u32__ret_i64"(i8* %"path.1", i32 %".4", i32 1, i32 3, i32 128)
  ret i64 %".5"
}

define i64 @"standard__io__file__open_write__1__byte_ptr1__ret_i64"(i8* %"path")
{
entry:
  %"path.addr" = alloca i8*
  store i8* %"path", i8** %"path.addr"
  %"path.1" = load i8*, i8** %"path.addr"
  %".4" = call i64 @"standard__io__file__win_open__5__byte_ptr1__u32__u32__u32__u32__ret_i64"(i8* %"path.1", i32 1073741824, i32 0, i32 2, i32 128)
  ret i64 %".4"
}

define i64 @"standard__io__file__open_append__1__byte_ptr1__ret_i64"(i8* %"path")
{
entry:
  %"path.addr" = alloca i8*
  store i8* %"path", i8** %"path.addr"
  %"path.1" = load i8*, i8** %"path.addr"
  %".4" = call i64 @"standard__io__file__win_open__5__byte_ptr1__u32__u32__u32__u32__ret_i64"(i8* %"path.1", i32 1073741824, i32 1, i32 4, i32 128)
  ret i64 %".4"
}

define i64 @"standard__io__file__open_read_write__1__byte_ptr1__ret_i64"(i8* %"path")
{
entry:
  %"path.addr" = alloca i8*
  store i8* %"path", i8** %"path.addr"
  %"path.1" = load i8*, i8** %"path.addr"
  %".4" = trunc i64 3221225472 to i32
  %".5" = call i64 @"standard__io__file__win_open__5__byte_ptr1__u32__u32__u32__u32__ret_i64"(i8* %"path.1", i32 %".4", i32 1, i32 4, i32 128)
  ret i64 %".5"
}

declare external i16* @"GetCommandLineW"()

declare external i16* @"CommandLineToArgvW"(i16* %"x", i32* %"y")

declare external i8* @"LocalFree"(i8* %"x")

define i32 @"main"()
{
entry:
  %"str_stack" = alloca [39 x i8]
  %"str_char_0" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 0
  store i8 84, i8* %"str_char_0"
  %"str_char_1" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 1
  store i8 101, i8* %"str_char_1"
  %"str_char_2" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 2
  store i8 115, i8* %"str_char_2"
  %"str_char_3" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 3
  store i8 116, i8* %"str_char_3"
  %"str_char_4" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 4
  store i8 105, i8* %"str_char_4"
  %"str_char_5" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 5
  store i8 110, i8* %"str_char_5"
  %"str_char_6" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 6
  store i8 103, i8* %"str_char_6"
  %"str_char_7" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 7
  store i8 32, i8* %"str_char_7"
  %"str_char_8" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 8
  store i8 54, i8* %"str_char_8"
  %"str_char_9" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 9
  store i8 52, i8* %"str_char_9"
  %"str_char_10" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 10
  store i8 45, i8* %"str_char_10"
  %"str_char_11" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 11
  store i8 98, i8* %"str_char_11"
  %"str_char_12" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 12
  store i8 105, i8* %"str_char_12"
  %"str_char_13" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 13
  store i8 116, i8* %"str_char_13"
  %"str_char_14" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 14
  store i8 32, i8* %"str_char_14"
  %"str_char_15" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 15
  store i8 97, i8* %"str_char_15"
  %"str_char_16" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 16
  store i8 114, i8* %"str_char_16"
  %"str_char_17" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 17
  store i8 105, i8* %"str_char_17"
  %"str_char_18" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 18
  store i8 116, i8* %"str_char_18"
  %"str_char_19" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 19
  store i8 104, i8* %"str_char_19"
  %"str_char_20" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 20
  store i8 109, i8* %"str_char_20"
  %"str_char_21" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 21
  store i8 101, i8* %"str_char_21"
  %"str_char_22" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 22
  store i8 116, i8* %"str_char_22"
  %"str_char_23" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 23
  store i8 105, i8* %"str_char_23"
  %"str_char_24" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 24
  store i8 99, i8* %"str_char_24"
  %"str_char_25" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 25
  store i8 32, i8* %"str_char_25"
  %"str_char_26" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 26
  store i8 111, i8* %"str_char_26"
  %"str_char_27" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 27
  store i8 112, i8* %"str_char_27"
  %"str_char_28" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 28
  store i8 101, i8* %"str_char_28"
  %"str_char_29" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 29
  store i8 114, i8* %"str_char_29"
  %"str_char_30" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 30
  store i8 97, i8* %"str_char_30"
  %"str_char_31" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 31
  store i8 116, i8* %"str_char_31"
  %"str_char_32" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 32
  store i8 105, i8* %"str_char_32"
  %"str_char_33" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 33
  store i8 111, i8* %"str_char_33"
  %"str_char_34" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 34
  store i8 110, i8* %"str_char_34"
  %"str_char_35" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 35
  store i8 115, i8* %"str_char_35"
  %"str_char_36" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 36
  store i8 58, i8* %"str_char_36"
  %"str_char_37" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 37
  store i8 10, i8* %"str_char_37"
  %"str_char_38" = getelementptr [39 x i8], [39 x i8]* %"str_stack", i32 0, i32 38
  store i8 0, i8* %"str_char_38"
  %"str_stack.1" = alloca [39 x i8]
  %"str_char_0.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 0
  store i8 84, i8* %"str_char_0.1"
  %"str_char_1.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 1
  store i8 101, i8* %"str_char_1.1"
  %"str_char_2.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 2
  store i8 115, i8* %"str_char_2.1"
  %"str_char_3.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 3
  store i8 116, i8* %"str_char_3.1"
  %"str_char_4.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 4
  store i8 105, i8* %"str_char_4.1"
  %"str_char_5.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 5
  store i8 110, i8* %"str_char_5.1"
  %"str_char_6.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 6
  store i8 103, i8* %"str_char_6.1"
  %"str_char_7.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 7
  store i8 32, i8* %"str_char_7.1"
  %"str_char_8.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 8
  store i8 54, i8* %"str_char_8.1"
  %"str_char_9.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 9
  store i8 52, i8* %"str_char_9.1"
  %"str_char_10.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 10
  store i8 45, i8* %"str_char_10.1"
  %"str_char_11.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 11
  store i8 98, i8* %"str_char_11.1"
  %"str_char_12.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 12
  store i8 105, i8* %"str_char_12.1"
  %"str_char_13.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 13
  store i8 116, i8* %"str_char_13.1"
  %"str_char_14.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 14
  store i8 32, i8* %"str_char_14.1"
  %"str_char_15.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 15
  store i8 97, i8* %"str_char_15.1"
  %"str_char_16.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 16
  store i8 114, i8* %"str_char_16.1"
  %"str_char_17.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 17
  store i8 105, i8* %"str_char_17.1"
  %"str_char_18.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 18
  store i8 116, i8* %"str_char_18.1"
  %"str_char_19.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 19
  store i8 104, i8* %"str_char_19.1"
  %"str_char_20.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 20
  store i8 109, i8* %"str_char_20.1"
  %"str_char_21.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 21
  store i8 101, i8* %"str_char_21.1"
  %"str_char_22.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 22
  store i8 116, i8* %"str_char_22.1"
  %"str_char_23.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 23
  store i8 105, i8* %"str_char_23.1"
  %"str_char_24.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 24
  store i8 99, i8* %"str_char_24.1"
  %"str_char_25.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 25
  store i8 32, i8* %"str_char_25.1"
  %"str_char_26.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 26
  store i8 111, i8* %"str_char_26.1"
  %"str_char_27.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 27
  store i8 112, i8* %"str_char_27.1"
  %"str_char_28.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 28
  store i8 101, i8* %"str_char_28.1"
  %"str_char_29.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 29
  store i8 114, i8* %"str_char_29.1"
  %"str_char_30.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 30
  store i8 97, i8* %"str_char_30.1"
  %"str_char_31.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 31
  store i8 116, i8* %"str_char_31.1"
  %"str_char_32.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 32
  store i8 105, i8* %"str_char_32.1"
  %"str_char_33.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 33
  store i8 111, i8* %"str_char_33.1"
  %"str_char_34.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 34
  store i8 110, i8* %"str_char_34.1"
  %"str_char_35.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 35
  store i8 115, i8* %"str_char_35.1"
  %"str_char_36.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 36
  store i8 58, i8* %"str_char_36.1"
  %"str_char_37.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 37
  store i8 10, i8* %"str_char_37.1"
  %"str_char_38.1" = getelementptr [39 x i8], [39 x i8]* %"str_stack.1", i32 0, i32 38
  store i8 0, i8* %"str_char_38.1"
  %"arg0_to_void_ptr" = bitcast [39 x i8]* %"str_stack.1" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr")
  %".81" = call i32 @"test_64bit_arithmetic__0__ret_int"()
  ret i32 %".81"
}

define i32 @"FRTStartup"()
{
entry:
  %"return_code" = alloca i32
  switch i32 1, label %"switch_default" [i32 1, label %"switch_case_0"]
switch_merge:
  %"return_code.2" = load i32, i32* %"return_code"
  %".7" = icmp ne i32 %"return_code.2", 0
  br i1 %".7", label %"then", label %"else"
switch_case_0:
  %".3" = call i32 @"main"()
  store i32 %".3", i32* %"return_code"
  br label %"switch_merge"
switch_default:
  %"return_code.1" = load i32, i32* %"return_code"
  ret i32 %"return_code.1"
then:
  br label %"ifcont"
else:
  br label %"ifcont"
ifcont:
  %"return_code.3" = load i32, i32* %"return_code"
  ret i32 %"return_code.3"
}

define i32 @"test_64bit_arithmetic__0__ret_int"()
{
entry:
  %"buffer" = alloca [32 x i8]
  %"large_val" = alloca i64
  store i64 5000000000, i64* %"large_val"
  %"divided" = alloca i64
  %"large_val.1" = load i64, i64* %"large_val"
  %".3" = sext i32 10 to i64
  %".4" = sdiv i64 %"large_val.1", %".3"
  store i64 %".4", i64* %"divided"
  %"modded" = alloca i64
  %"large_val.2" = load i64, i64* %"large_val"
  %".6" = sext i32 10 to i64
  %".7" = srem i64 %"large_val.2", %".6"
  store i64 %".7", i64* %"modded"
  %"str_stack" = alloca [19 x i8]
  %"str_char_0" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 0
  store i8 53, i8* %"str_char_0"
  %"str_char_1" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 1
  store i8 48, i8* %"str_char_1"
  %"str_char_2" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 2
  store i8 48, i8* %"str_char_2"
  %"str_char_3" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 3
  store i8 48, i8* %"str_char_3"
  %"str_char_4" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 4
  store i8 48, i8* %"str_char_4"
  %"str_char_5" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 5
  store i8 48, i8* %"str_char_5"
  %"str_char_6" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 6
  store i8 48, i8* %"str_char_6"
  %"str_char_7" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 7
  store i8 48, i8* %"str_char_7"
  %"str_char_8" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 8
  store i8 48, i8* %"str_char_8"
  %"str_char_9" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 9
  store i8 48, i8* %"str_char_9"
  %"str_char_10" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 10
  store i8 32, i8* %"str_char_10"
  %"str_char_11" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 11
  store i8 47, i8* %"str_char_11"
  %"str_char_12" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 12
  store i8 32, i8* %"str_char_12"
  %"str_char_13" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 13
  store i8 49, i8* %"str_char_13"
  %"str_char_14" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 14
  store i8 48, i8* %"str_char_14"
  %"str_char_15" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 15
  store i8 32, i8* %"str_char_15"
  %"str_char_16" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 16
  store i8 61, i8* %"str_char_16"
  %"str_char_17" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 17
  store i8 32, i8* %"str_char_17"
  %"str_char_18" = getelementptr [19 x i8], [19 x i8]* %"str_stack", i32 0, i32 18
  store i8 0, i8* %"str_char_18"
  %"str_stack.1" = alloca [19 x i8]
  %"str_char_0.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 0
  store i8 53, i8* %"str_char_0.1"
  %"str_char_1.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 1
  store i8 48, i8* %"str_char_1.1"
  %"str_char_2.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 2
  store i8 48, i8* %"str_char_2.1"
  %"str_char_3.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 3
  store i8 48, i8* %"str_char_3.1"
  %"str_char_4.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 4
  store i8 48, i8* %"str_char_4.1"
  %"str_char_5.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 5
  store i8 48, i8* %"str_char_5.1"
  %"str_char_6.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 6
  store i8 48, i8* %"str_char_6.1"
  %"str_char_7.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 7
  store i8 48, i8* %"str_char_7.1"
  %"str_char_8.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 8
  store i8 48, i8* %"str_char_8.1"
  %"str_char_9.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 9
  store i8 48, i8* %"str_char_9.1"
  %"str_char_10.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 10
  store i8 32, i8* %"str_char_10.1"
  %"str_char_11.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 11
  store i8 47, i8* %"str_char_11.1"
  %"str_char_12.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 12
  store i8 32, i8* %"str_char_12.1"
  %"str_char_13.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 13
  store i8 49, i8* %"str_char_13.1"
  %"str_char_14.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 14
  store i8 48, i8* %"str_char_14.1"
  %"str_char_15.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 15
  store i8 32, i8* %"str_char_15.1"
  %"str_char_16.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 16
  store i8 61, i8* %"str_char_16.1"
  %"str_char_17.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 17
  store i8 32, i8* %"str_char_17.1"
  %"str_char_18.1" = getelementptr [19 x i8], [19 x i8]* %"str_stack.1", i32 0, i32 18
  store i8 0, i8* %"str_char_18.1"
  %"arg0_to_void_ptr" = bitcast [19 x i8]* %"str_stack.1" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr")
  %"divided.1" = load i64, i64* %"divided"
  %"arg1_to_void_ptr" = bitcast [32 x i8]* %"buffer" to i8*
  %".48" = call i64 @"u64str__2__u64__byte_ptr1__ret_u64"(i64 %"divided.1", i8* %"arg1_to_void_ptr")
  %"arg0_to_void_ptr.1" = bitcast [32 x i8]* %"buffer" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr.1")
  %"str_stack.2" = alloca [24 x i8]
  %"str_char_0.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 0
  store i8 32, i8* %"str_char_0.2"
  %"str_char_1.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 1
  store i8 40, i8* %"str_char_1.2"
  %"str_char_2.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 2
  store i8 101, i8* %"str_char_2.2"
  %"str_char_3.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 3
  store i8 120, i8* %"str_char_3.2"
  %"str_char_4.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 4
  store i8 112, i8* %"str_char_4.2"
  %"str_char_5.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 5
  store i8 101, i8* %"str_char_5.2"
  %"str_char_6.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 6
  store i8 99, i8* %"str_char_6.2"
  %"str_char_7.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 7
  store i8 116, i8* %"str_char_7.2"
  %"str_char_8.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 8
  store i8 101, i8* %"str_char_8.2"
  %"str_char_9.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 9
  store i8 100, i8* %"str_char_9.2"
  %"str_char_10.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 10
  store i8 58, i8* %"str_char_10.2"
  %"str_char_11.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 11
  store i8 32, i8* %"str_char_11.2"
  %"str_char_12.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 12
  store i8 53, i8* %"str_char_12.2"
  %"str_char_13.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 13
  store i8 48, i8* %"str_char_13.2"
  %"str_char_14.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 14
  store i8 48, i8* %"str_char_14.2"
  %"str_char_15.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 15
  store i8 48, i8* %"str_char_15.2"
  %"str_char_16.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 16
  store i8 48, i8* %"str_char_16.2"
  %"str_char_17.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 17
  store i8 48, i8* %"str_char_17.2"
  %"str_char_18.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 18
  store i8 48, i8* %"str_char_18.2"
  %"str_char_19" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 19
  store i8 48, i8* %"str_char_19"
  %"str_char_20" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 20
  store i8 48, i8* %"str_char_20"
  %"str_char_21" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 21
  store i8 41, i8* %"str_char_21"
  %"str_char_22" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 22
  store i8 10, i8* %"str_char_22"
  %"str_char_23" = getelementptr [24 x i8], [24 x i8]* %"str_stack.2", i32 0, i32 23
  store i8 0, i8* %"str_char_23"
  %"str_stack.3" = alloca [24 x i8]
  %"str_char_0.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 0
  store i8 32, i8* %"str_char_0.3"
  %"str_char_1.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 1
  store i8 40, i8* %"str_char_1.3"
  %"str_char_2.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 2
  store i8 101, i8* %"str_char_2.3"
  %"str_char_3.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 3
  store i8 120, i8* %"str_char_3.3"
  %"str_char_4.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 4
  store i8 112, i8* %"str_char_4.3"
  %"str_char_5.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 5
  store i8 101, i8* %"str_char_5.3"
  %"str_char_6.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 6
  store i8 99, i8* %"str_char_6.3"
  %"str_char_7.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 7
  store i8 116, i8* %"str_char_7.3"
  %"str_char_8.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 8
  store i8 101, i8* %"str_char_8.3"
  %"str_char_9.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 9
  store i8 100, i8* %"str_char_9.3"
  %"str_char_10.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 10
  store i8 58, i8* %"str_char_10.3"
  %"str_char_11.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 11
  store i8 32, i8* %"str_char_11.3"
  %"str_char_12.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 12
  store i8 53, i8* %"str_char_12.3"
  %"str_char_13.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 13
  store i8 48, i8* %"str_char_13.3"
  %"str_char_14.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 14
  store i8 48, i8* %"str_char_14.3"
  %"str_char_15.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 15
  store i8 48, i8* %"str_char_15.3"
  %"str_char_16.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 16
  store i8 48, i8* %"str_char_16.3"
  %"str_char_17.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 17
  store i8 48, i8* %"str_char_17.3"
  %"str_char_18.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 18
  store i8 48, i8* %"str_char_18.3"
  %"str_char_19.1" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 19
  store i8 48, i8* %"str_char_19.1"
  %"str_char_20.1" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 20
  store i8 48, i8* %"str_char_20.1"
  %"str_char_21.1" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 21
  store i8 41, i8* %"str_char_21.1"
  %"str_char_22.1" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 22
  store i8 10, i8* %"str_char_22.1"
  %"str_char_23.1" = getelementptr [24 x i8], [24 x i8]* %"str_stack.3", i32 0, i32 23
  store i8 0, i8* %"str_char_23.1"
  %"arg0_to_void_ptr.2" = bitcast [24 x i8]* %"str_stack.3" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr.2")
  %"str_stack.4" = alloca [19 x i8]
  %"str_char_0.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 0
  store i8 53, i8* %"str_char_0.4"
  %"str_char_1.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 1
  store i8 48, i8* %"str_char_1.4"
  %"str_char_2.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 2
  store i8 48, i8* %"str_char_2.4"
  %"str_char_3.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 3
  store i8 48, i8* %"str_char_3.4"
  %"str_char_4.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 4
  store i8 48, i8* %"str_char_4.4"
  %"str_char_5.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 5
  store i8 48, i8* %"str_char_5.4"
  %"str_char_6.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 6
  store i8 48, i8* %"str_char_6.4"
  %"str_char_7.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 7
  store i8 48, i8* %"str_char_7.4"
  %"str_char_8.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 8
  store i8 48, i8* %"str_char_8.4"
  %"str_char_9.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 9
  store i8 48, i8* %"str_char_9.4"
  %"str_char_10.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 10
  store i8 32, i8* %"str_char_10.4"
  %"str_char_11.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 11
  store i8 37, i8* %"str_char_11.4"
  %"str_char_12.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 12
  store i8 32, i8* %"str_char_12.4"
  %"str_char_13.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 13
  store i8 49, i8* %"str_char_13.4"
  %"str_char_14.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 14
  store i8 48, i8* %"str_char_14.4"
  %"str_char_15.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 15
  store i8 32, i8* %"str_char_15.4"
  %"str_char_16.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 16
  store i8 61, i8* %"str_char_16.4"
  %"str_char_17.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 17
  store i8 32, i8* %"str_char_17.4"
  %"str_char_18.4" = getelementptr [19 x i8], [19 x i8]* %"str_stack.4", i32 0, i32 18
  store i8 0, i8* %"str_char_18.4"
  %"str_stack.5" = alloca [19 x i8]
  %"str_char_0.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 0
  store i8 53, i8* %"str_char_0.5"
  %"str_char_1.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 1
  store i8 48, i8* %"str_char_1.5"
  %"str_char_2.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 2
  store i8 48, i8* %"str_char_2.5"
  %"str_char_3.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 3
  store i8 48, i8* %"str_char_3.5"
  %"str_char_4.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 4
  store i8 48, i8* %"str_char_4.5"
  %"str_char_5.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 5
  store i8 48, i8* %"str_char_5.5"
  %"str_char_6.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 6
  store i8 48, i8* %"str_char_6.5"
  %"str_char_7.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 7
  store i8 48, i8* %"str_char_7.5"
  %"str_char_8.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 8
  store i8 48, i8* %"str_char_8.5"
  %"str_char_9.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 9
  store i8 48, i8* %"str_char_9.5"
  %"str_char_10.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 10
  store i8 32, i8* %"str_char_10.5"
  %"str_char_11.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 11
  store i8 37, i8* %"str_char_11.5"
  %"str_char_12.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 12
  store i8 32, i8* %"str_char_12.5"
  %"str_char_13.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 13
  store i8 49, i8* %"str_char_13.5"
  %"str_char_14.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 14
  store i8 48, i8* %"str_char_14.5"
  %"str_char_15.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 15
  store i8 32, i8* %"str_char_15.5"
  %"str_char_16.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 16
  store i8 61, i8* %"str_char_16.5"
  %"str_char_17.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 17
  store i8 32, i8* %"str_char_17.5"
  %"str_char_18.5" = getelementptr [19 x i8], [19 x i8]* %"str_stack.5", i32 0, i32 18
  store i8 0, i8* %"str_char_18.5"
  %"arg0_to_void_ptr.3" = bitcast [19 x i8]* %"str_stack.5" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr.3")
  %"modded.1" = load i64, i64* %"modded"
  %"arg1_to_void_ptr.1" = bitcast [32 x i8]* %"buffer" to i8*
  %".138" = call i64 @"u64str__2__u64__byte_ptr1__ret_u64"(i64 %"modded.1", i8* %"arg1_to_void_ptr.1")
  %"arg0_to_void_ptr.4" = bitcast [32 x i8]* %"buffer" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr.4")
  %"str_stack.6" = alloca [16 x i8]
  %"str_char_0.6" = getelementptr [16 x i8], [16 x i8]* %"str_stack.6", i32 0, i32 0
  store i8 32, i8* %"str_char_0.6"
  %"str_char_1.6" = getelementptr [16 x i8], [16 x i8]* %"str_stack.6", i32 0, i32 1
  store i8 40, i8* %"str_char_1.6"
  %"str_char_2.6" = getelementptr [16 x i8], [16 x i8]* %"str_stack.6", i32 0, i32 2
  store i8 101, i8* %"str_char_2.6"
  %"str_char_3.6" = getelementptr [16 x i8], [16 x i8]* %"str_stack.6", i32 0, i32 3
  store i8 120, i8* %"str_char_3.6"
  %"str_char_4.6" = getelementptr [16 x i8], [16 x i8]* %"str_stack.6", i32 0, i32 4
  store i8 112, i8* %"str_char_4.6"
  %"str_char_5.6" = getelementptr [16 x i8], [16 x i8]* %"str_stack.6", i32 0, i32 5
  store i8 101, i8* %"str_char_5.6"
  %"str_char_6.6" = getelementptr [16 x i8], [16 x i8]* %"str_stack.6", i32 0, i32 6
  store i8 99, i8* %"str_char_6.6"
  %"str_char_7.6" = getelementptr [16 x i8], [16 x i8]* %"str_stack.6", i32 0, i32 7
  store i8 116, i8* %"str_char_7.6"
  %"str_char_8.6" = getelementptr [16 x i8], [16 x i8]* %"str_stack.6", i32 0, i32 8
  store i8 101, i8* %"str_char_8.6"
  %"str_char_9.6" = getelementptr [16 x i8], [16 x i8]* %"str_stack.6", i32 0, i32 9
  store i8 100, i8* %"str_char_9.6"
  %"str_char_10.6" = getelementptr [16 x i8], [16 x i8]* %"str_stack.6", i32 0, i32 10
  store i8 58, i8* %"str_char_10.6"
  %"str_char_11.6" = getelementptr [16 x i8], [16 x i8]* %"str_stack.6", i32 0, i32 11
  store i8 32, i8* %"str_char_11.6"
  %"str_char_12.6" = getelementptr [16 x i8], [16 x i8]* %"str_stack.6", i32 0, i32 12
  store i8 48, i8* %"str_char_12.6"
  %"str_char_13.6" = getelementptr [16 x i8], [16 x i8]* %"str_stack.6", i32 0, i32 13
  store i8 41, i8* %"str_char_13.6"
  %"str_char_14.6" = getelementptr [16 x i8], [16 x i8]* %"str_stack.6", i32 0, i32 14
  store i8 10, i8* %"str_char_14.6"
  %"str_char_15.6" = getelementptr [16 x i8], [16 x i8]* %"str_stack.6", i32 0, i32 15
  store i8 0, i8* %"str_char_15.6"
  %"str_stack.7" = alloca [16 x i8]
  %"str_char_0.7" = getelementptr [16 x i8], [16 x i8]* %"str_stack.7", i32 0, i32 0
  store i8 32, i8* %"str_char_0.7"
  %"str_char_1.7" = getelementptr [16 x i8], [16 x i8]* %"str_stack.7", i32 0, i32 1
  store i8 40, i8* %"str_char_1.7"
  %"str_char_2.7" = getelementptr [16 x i8], [16 x i8]* %"str_stack.7", i32 0, i32 2
  store i8 101, i8* %"str_char_2.7"
  %"str_char_3.7" = getelementptr [16 x i8], [16 x i8]* %"str_stack.7", i32 0, i32 3
  store i8 120, i8* %"str_char_3.7"
  %"str_char_4.7" = getelementptr [16 x i8], [16 x i8]* %"str_stack.7", i32 0, i32 4
  store i8 112, i8* %"str_char_4.7"
  %"str_char_5.7" = getelementptr [16 x i8], [16 x i8]* %"str_stack.7", i32 0, i32 5
  store i8 101, i8* %"str_char_5.7"
  %"str_char_6.7" = getelementptr [16 x i8], [16 x i8]* %"str_stack.7", i32 0, i32 6
  store i8 99, i8* %"str_char_6.7"
  %"str_char_7.7" = getelementptr [16 x i8], [16 x i8]* %"str_stack.7", i32 0, i32 7
  store i8 116, i8* %"str_char_7.7"
  %"str_char_8.7" = getelementptr [16 x i8], [16 x i8]* %"str_stack.7", i32 0, i32 8
  store i8 101, i8* %"str_char_8.7"
  %"str_char_9.7" = getelementptr [16 x i8], [16 x i8]* %"str_stack.7", i32 0, i32 9
  store i8 100, i8* %"str_char_9.7"
  %"str_char_10.7" = getelementptr [16 x i8], [16 x i8]* %"str_stack.7", i32 0, i32 10
  store i8 58, i8* %"str_char_10.7"
  %"str_char_11.7" = getelementptr [16 x i8], [16 x i8]* %"str_stack.7", i32 0, i32 11
  store i8 32, i8* %"str_char_11.7"
  %"str_char_12.7" = getelementptr [16 x i8], [16 x i8]* %"str_stack.7", i32 0, i32 12
  store i8 48, i8* %"str_char_12.7"
  %"str_char_13.7" = getelementptr [16 x i8], [16 x i8]* %"str_stack.7", i32 0, i32 13
  store i8 41, i8* %"str_char_13.7"
  %"str_char_14.7" = getelementptr [16 x i8], [16 x i8]* %"str_stack.7", i32 0, i32 14
  store i8 10, i8* %"str_char_14.7"
  %"str_char_15.7" = getelementptr [16 x i8], [16 x i8]* %"str_stack.7", i32 0, i32 15
  store i8 0, i8* %"str_char_15.7"
  %"arg0_to_void_ptr.5" = bitcast [16 x i8]* %"str_stack.7" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr.5")
  %"small_val" = alloca i64
  %".173" = sext i32 12345 to i64
  store i64 %".173", i64* %"small_val"
  %"small_div" = alloca i64
  %"small_val.1" = load i64, i64* %"small_val"
  %".175" = sext i32 10 to i64
  %".176" = sdiv i64 %"small_val.1", %".175"
  store i64 %".176", i64* %"small_div"
  %"small_mod" = alloca i64
  %"small_val.2" = load i64, i64* %"small_val"
  %".178" = sext i32 10 to i64
  %".179" = srem i64 %"small_val.2", %".178"
  store i64 %".179", i64* %"small_mod"
  %"str_stack.8" = alloca [14 x i8]
  %"str_char_0.8" = getelementptr [14 x i8], [14 x i8]* %"str_stack.8", i32 0, i32 0
  store i8 49, i8* %"str_char_0.8"
  %"str_char_1.8" = getelementptr [14 x i8], [14 x i8]* %"str_stack.8", i32 0, i32 1
  store i8 50, i8* %"str_char_1.8"
  %"str_char_2.8" = getelementptr [14 x i8], [14 x i8]* %"str_stack.8", i32 0, i32 2
  store i8 51, i8* %"str_char_2.8"
  %"str_char_3.8" = getelementptr [14 x i8], [14 x i8]* %"str_stack.8", i32 0, i32 3
  store i8 52, i8* %"str_char_3.8"
  %"str_char_4.8" = getelementptr [14 x i8], [14 x i8]* %"str_stack.8", i32 0, i32 4
  store i8 53, i8* %"str_char_4.8"
  %"str_char_5.8" = getelementptr [14 x i8], [14 x i8]* %"str_stack.8", i32 0, i32 5
  store i8 32, i8* %"str_char_5.8"
  %"str_char_6.8" = getelementptr [14 x i8], [14 x i8]* %"str_stack.8", i32 0, i32 6
  store i8 47, i8* %"str_char_6.8"
  %"str_char_7.8" = getelementptr [14 x i8], [14 x i8]* %"str_stack.8", i32 0, i32 7
  store i8 32, i8* %"str_char_7.8"
  %"str_char_8.8" = getelementptr [14 x i8], [14 x i8]* %"str_stack.8", i32 0, i32 8
  store i8 49, i8* %"str_char_8.8"
  %"str_char_9.8" = getelementptr [14 x i8], [14 x i8]* %"str_stack.8", i32 0, i32 9
  store i8 48, i8* %"str_char_9.8"
  %"str_char_10.8" = getelementptr [14 x i8], [14 x i8]* %"str_stack.8", i32 0, i32 10
  store i8 32, i8* %"str_char_10.8"
  %"str_char_11.8" = getelementptr [14 x i8], [14 x i8]* %"str_stack.8", i32 0, i32 11
  store i8 61, i8* %"str_char_11.8"
  %"str_char_12.8" = getelementptr [14 x i8], [14 x i8]* %"str_stack.8", i32 0, i32 12
  store i8 32, i8* %"str_char_12.8"
  %"str_char_13.8" = getelementptr [14 x i8], [14 x i8]* %"str_stack.8", i32 0, i32 13
  store i8 0, i8* %"str_char_13.8"
  %"str_stack.9" = alloca [14 x i8]
  %"str_char_0.9" = getelementptr [14 x i8], [14 x i8]* %"str_stack.9", i32 0, i32 0
  store i8 49, i8* %"str_char_0.9"
  %"str_char_1.9" = getelementptr [14 x i8], [14 x i8]* %"str_stack.9", i32 0, i32 1
  store i8 50, i8* %"str_char_1.9"
  %"str_char_2.9" = getelementptr [14 x i8], [14 x i8]* %"str_stack.9", i32 0, i32 2
  store i8 51, i8* %"str_char_2.9"
  %"str_char_3.9" = getelementptr [14 x i8], [14 x i8]* %"str_stack.9", i32 0, i32 3
  store i8 52, i8* %"str_char_3.9"
  %"str_char_4.9" = getelementptr [14 x i8], [14 x i8]* %"str_stack.9", i32 0, i32 4
  store i8 53, i8* %"str_char_4.9"
  %"str_char_5.9" = getelementptr [14 x i8], [14 x i8]* %"str_stack.9", i32 0, i32 5
  store i8 32, i8* %"str_char_5.9"
  %"str_char_6.9" = getelementptr [14 x i8], [14 x i8]* %"str_stack.9", i32 0, i32 6
  store i8 47, i8* %"str_char_6.9"
  %"str_char_7.9" = getelementptr [14 x i8], [14 x i8]* %"str_stack.9", i32 0, i32 7
  store i8 32, i8* %"str_char_7.9"
  %"str_char_8.9" = getelementptr [14 x i8], [14 x i8]* %"str_stack.9", i32 0, i32 8
  store i8 49, i8* %"str_char_8.9"
  %"str_char_9.9" = getelementptr [14 x i8], [14 x i8]* %"str_stack.9", i32 0, i32 9
  store i8 48, i8* %"str_char_9.9"
  %"str_char_10.9" = getelementptr [14 x i8], [14 x i8]* %"str_stack.9", i32 0, i32 10
  store i8 32, i8* %"str_char_10.9"
  %"str_char_11.9" = getelementptr [14 x i8], [14 x i8]* %"str_stack.9", i32 0, i32 11
  store i8 61, i8* %"str_char_11.9"
  %"str_char_12.9" = getelementptr [14 x i8], [14 x i8]* %"str_stack.9", i32 0, i32 12
  store i8 32, i8* %"str_char_12.9"
  %"str_char_13.9" = getelementptr [14 x i8], [14 x i8]* %"str_stack.9", i32 0, i32 13
  store i8 0, i8* %"str_char_13.9"
  %"arg0_to_void_ptr.6" = bitcast [14 x i8]* %"str_stack.9" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr.6")
  %"small_div.1" = load i64, i64* %"small_div"
  %"arg1_to_void_ptr.2" = bitcast [32 x i8]* %"buffer" to i8*
  %".210" = call i64 @"u64str__2__u64__byte_ptr1__ret_u64"(i64 %"small_div.1", i8* %"arg1_to_void_ptr.2")
  %"arg0_to_void_ptr.7" = bitcast [32 x i8]* %"buffer" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr.7")
  %"str_stack.10" = alloca [19 x i8]
  %"str_char_0.10" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 0
  store i8 32, i8* %"str_char_0.10"
  %"str_char_1.10" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 1
  store i8 40, i8* %"str_char_1.10"
  %"str_char_2.10" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 2
  store i8 101, i8* %"str_char_2.10"
  %"str_char_3.10" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 3
  store i8 120, i8* %"str_char_3.10"
  %"str_char_4.10" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 4
  store i8 112, i8* %"str_char_4.10"
  %"str_char_5.10" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 5
  store i8 101, i8* %"str_char_5.10"
  %"str_char_6.10" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 6
  store i8 99, i8* %"str_char_6.10"
  %"str_char_7.10" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 7
  store i8 116, i8* %"str_char_7.10"
  %"str_char_8.10" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 8
  store i8 101, i8* %"str_char_8.10"
  %"str_char_9.10" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 9
  store i8 100, i8* %"str_char_9.10"
  %"str_char_10.10" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 10
  store i8 58, i8* %"str_char_10.10"
  %"str_char_11.10" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 11
  store i8 32, i8* %"str_char_11.10"
  %"str_char_12.10" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 12
  store i8 49, i8* %"str_char_12.10"
  %"str_char_13.10" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 13
  store i8 50, i8* %"str_char_13.10"
  %"str_char_14.8" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 14
  store i8 51, i8* %"str_char_14.8"
  %"str_char_15.8" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 15
  store i8 52, i8* %"str_char_15.8"
  %"str_char_16.6" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 16
  store i8 41, i8* %"str_char_16.6"
  %"str_char_17.6" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 17
  store i8 10, i8* %"str_char_17.6"
  %"str_char_18.6" = getelementptr [19 x i8], [19 x i8]* %"str_stack.10", i32 0, i32 18
  store i8 0, i8* %"str_char_18.6"
  %"str_stack.11" = alloca [19 x i8]
  %"str_char_0.11" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 0
  store i8 32, i8* %"str_char_0.11"
  %"str_char_1.11" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 1
  store i8 40, i8* %"str_char_1.11"
  %"str_char_2.11" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 2
  store i8 101, i8* %"str_char_2.11"
  %"str_char_3.11" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 3
  store i8 120, i8* %"str_char_3.11"
  %"str_char_4.11" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 4
  store i8 112, i8* %"str_char_4.11"
  %"str_char_5.11" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 5
  store i8 101, i8* %"str_char_5.11"
  %"str_char_6.11" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 6
  store i8 99, i8* %"str_char_6.11"
  %"str_char_7.11" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 7
  store i8 116, i8* %"str_char_7.11"
  %"str_char_8.11" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 8
  store i8 101, i8* %"str_char_8.11"
  %"str_char_9.11" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 9
  store i8 100, i8* %"str_char_9.11"
  %"str_char_10.11" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 10
  store i8 58, i8* %"str_char_10.11"
  %"str_char_11.11" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 11
  store i8 32, i8* %"str_char_11.11"
  %"str_char_12.11" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 12
  store i8 49, i8* %"str_char_12.11"
  %"str_char_13.11" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 13
  store i8 50, i8* %"str_char_13.11"
  %"str_char_14.9" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 14
  store i8 51, i8* %"str_char_14.9"
  %"str_char_15.9" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 15
  store i8 52, i8* %"str_char_15.9"
  %"str_char_16.7" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 16
  store i8 41, i8* %"str_char_16.7"
  %"str_char_17.7" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 17
  store i8 10, i8* %"str_char_17.7"
  %"str_char_18.7" = getelementptr [19 x i8], [19 x i8]* %"str_stack.11", i32 0, i32 18
  store i8 0, i8* %"str_char_18.7"
  %"arg0_to_void_ptr.8" = bitcast [19 x i8]* %"str_stack.11" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr.8")
  %"str_stack.12" = alloca [14 x i8]
  %"str_char_0.12" = getelementptr [14 x i8], [14 x i8]* %"str_stack.12", i32 0, i32 0
  store i8 49, i8* %"str_char_0.12"
  %"str_char_1.12" = getelementptr [14 x i8], [14 x i8]* %"str_stack.12", i32 0, i32 1
  store i8 50, i8* %"str_char_1.12"
  %"str_char_2.12" = getelementptr [14 x i8], [14 x i8]* %"str_stack.12", i32 0, i32 2
  store i8 51, i8* %"str_char_2.12"
  %"str_char_3.12" = getelementptr [14 x i8], [14 x i8]* %"str_stack.12", i32 0, i32 3
  store i8 52, i8* %"str_char_3.12"
  %"str_char_4.12" = getelementptr [14 x i8], [14 x i8]* %"str_stack.12", i32 0, i32 4
  store i8 53, i8* %"str_char_4.12"
  %"str_char_5.12" = getelementptr [14 x i8], [14 x i8]* %"str_stack.12", i32 0, i32 5
  store i8 32, i8* %"str_char_5.12"
  %"str_char_6.12" = getelementptr [14 x i8], [14 x i8]* %"str_stack.12", i32 0, i32 6
  store i8 37, i8* %"str_char_6.12"
  %"str_char_7.12" = getelementptr [14 x i8], [14 x i8]* %"str_stack.12", i32 0, i32 7
  store i8 32, i8* %"str_char_7.12"
  %"str_char_8.12" = getelementptr [14 x i8], [14 x i8]* %"str_stack.12", i32 0, i32 8
  store i8 49, i8* %"str_char_8.12"
  %"str_char_9.12" = getelementptr [14 x i8], [14 x i8]* %"str_stack.12", i32 0, i32 9
  store i8 48, i8* %"str_char_9.12"
  %"str_char_10.12" = getelementptr [14 x i8], [14 x i8]* %"str_stack.12", i32 0, i32 10
  store i8 32, i8* %"str_char_10.12"
  %"str_char_11.12" = getelementptr [14 x i8], [14 x i8]* %"str_stack.12", i32 0, i32 11
  store i8 61, i8* %"str_char_11.12"
  %"str_char_12.12" = getelementptr [14 x i8], [14 x i8]* %"str_stack.12", i32 0, i32 12
  store i8 32, i8* %"str_char_12.12"
  %"str_char_13.12" = getelementptr [14 x i8], [14 x i8]* %"str_stack.12", i32 0, i32 13
  store i8 0, i8* %"str_char_13.12"
  %"str_stack.13" = alloca [14 x i8]
  %"str_char_0.13" = getelementptr [14 x i8], [14 x i8]* %"str_stack.13", i32 0, i32 0
  store i8 49, i8* %"str_char_0.13"
  %"str_char_1.13" = getelementptr [14 x i8], [14 x i8]* %"str_stack.13", i32 0, i32 1
  store i8 50, i8* %"str_char_1.13"
  %"str_char_2.13" = getelementptr [14 x i8], [14 x i8]* %"str_stack.13", i32 0, i32 2
  store i8 51, i8* %"str_char_2.13"
  %"str_char_3.13" = getelementptr [14 x i8], [14 x i8]* %"str_stack.13", i32 0, i32 3
  store i8 52, i8* %"str_char_3.13"
  %"str_char_4.13" = getelementptr [14 x i8], [14 x i8]* %"str_stack.13", i32 0, i32 4
  store i8 53, i8* %"str_char_4.13"
  %"str_char_5.13" = getelementptr [14 x i8], [14 x i8]* %"str_stack.13", i32 0, i32 5
  store i8 32, i8* %"str_char_5.13"
  %"str_char_6.13" = getelementptr [14 x i8], [14 x i8]* %"str_stack.13", i32 0, i32 6
  store i8 37, i8* %"str_char_6.13"
  %"str_char_7.13" = getelementptr [14 x i8], [14 x i8]* %"str_stack.13", i32 0, i32 7
  store i8 32, i8* %"str_char_7.13"
  %"str_char_8.13" = getelementptr [14 x i8], [14 x i8]* %"str_stack.13", i32 0, i32 8
  store i8 49, i8* %"str_char_8.13"
  %"str_char_9.13" = getelementptr [14 x i8], [14 x i8]* %"str_stack.13", i32 0, i32 9
  store i8 48, i8* %"str_char_9.13"
  %"str_char_10.13" = getelementptr [14 x i8], [14 x i8]* %"str_stack.13", i32 0, i32 10
  store i8 32, i8* %"str_char_10.13"
  %"str_char_11.13" = getelementptr [14 x i8], [14 x i8]* %"str_stack.13", i32 0, i32 11
  store i8 61, i8* %"str_char_11.13"
  %"str_char_12.13" = getelementptr [14 x i8], [14 x i8]* %"str_stack.13", i32 0, i32 12
  store i8 32, i8* %"str_char_12.13"
  %"str_char_13.13" = getelementptr [14 x i8], [14 x i8]* %"str_stack.13", i32 0, i32 13
  store i8 0, i8* %"str_char_13.13"
  %"arg0_to_void_ptr.9" = bitcast [14 x i8]* %"str_stack.13" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr.9")
  %"small_mod.1" = load i64, i64* %"small_mod"
  %"arg1_to_void_ptr.3" = bitcast [32 x i8]* %"buffer" to i8*
  %".280" = call i64 @"u64str__2__u64__byte_ptr1__ret_u64"(i64 %"small_mod.1", i8* %"arg1_to_void_ptr.3")
  %"arg0_to_void_ptr.10" = bitcast [32 x i8]* %"buffer" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr.10")
  %"str_stack.14" = alloca [16 x i8]
  %"str_char_0.14" = getelementptr [16 x i8], [16 x i8]* %"str_stack.14", i32 0, i32 0
  store i8 32, i8* %"str_char_0.14"
  %"str_char_1.14" = getelementptr [16 x i8], [16 x i8]* %"str_stack.14", i32 0, i32 1
  store i8 40, i8* %"str_char_1.14"
  %"str_char_2.14" = getelementptr [16 x i8], [16 x i8]* %"str_stack.14", i32 0, i32 2
  store i8 101, i8* %"str_char_2.14"
  %"str_char_3.14" = getelementptr [16 x i8], [16 x i8]* %"str_stack.14", i32 0, i32 3
  store i8 120, i8* %"str_char_3.14"
  %"str_char_4.14" = getelementptr [16 x i8], [16 x i8]* %"str_stack.14", i32 0, i32 4
  store i8 112, i8* %"str_char_4.14"
  %"str_char_5.14" = getelementptr [16 x i8], [16 x i8]* %"str_stack.14", i32 0, i32 5
  store i8 101, i8* %"str_char_5.14"
  %"str_char_6.14" = getelementptr [16 x i8], [16 x i8]* %"str_stack.14", i32 0, i32 6
  store i8 99, i8* %"str_char_6.14"
  %"str_char_7.14" = getelementptr [16 x i8], [16 x i8]* %"str_stack.14", i32 0, i32 7
  store i8 116, i8* %"str_char_7.14"
  %"str_char_8.14" = getelementptr [16 x i8], [16 x i8]* %"str_stack.14", i32 0, i32 8
  store i8 101, i8* %"str_char_8.14"
  %"str_char_9.14" = getelementptr [16 x i8], [16 x i8]* %"str_stack.14", i32 0, i32 9
  store i8 100, i8* %"str_char_9.14"
  %"str_char_10.14" = getelementptr [16 x i8], [16 x i8]* %"str_stack.14", i32 0, i32 10
  store i8 58, i8* %"str_char_10.14"
  %"str_char_11.14" = getelementptr [16 x i8], [16 x i8]* %"str_stack.14", i32 0, i32 11
  store i8 32, i8* %"str_char_11.14"
  %"str_char_12.14" = getelementptr [16 x i8], [16 x i8]* %"str_stack.14", i32 0, i32 12
  store i8 53, i8* %"str_char_12.14"
  %"str_char_13.14" = getelementptr [16 x i8], [16 x i8]* %"str_stack.14", i32 0, i32 13
  store i8 41, i8* %"str_char_13.14"
  %"str_char_14.10" = getelementptr [16 x i8], [16 x i8]* %"str_stack.14", i32 0, i32 14
  store i8 10, i8* %"str_char_14.10"
  %"str_char_15.10" = getelementptr [16 x i8], [16 x i8]* %"str_stack.14", i32 0, i32 15
  store i8 0, i8* %"str_char_15.10"
  %"str_stack.15" = alloca [16 x i8]
  %"str_char_0.15" = getelementptr [16 x i8], [16 x i8]* %"str_stack.15", i32 0, i32 0
  store i8 32, i8* %"str_char_0.15"
  %"str_char_1.15" = getelementptr [16 x i8], [16 x i8]* %"str_stack.15", i32 0, i32 1
  store i8 40, i8* %"str_char_1.15"
  %"str_char_2.15" = getelementptr [16 x i8], [16 x i8]* %"str_stack.15", i32 0, i32 2
  store i8 101, i8* %"str_char_2.15"
  %"str_char_3.15" = getelementptr [16 x i8], [16 x i8]* %"str_stack.15", i32 0, i32 3
  store i8 120, i8* %"str_char_3.15"
  %"str_char_4.15" = getelementptr [16 x i8], [16 x i8]* %"str_stack.15", i32 0, i32 4
  store i8 112, i8* %"str_char_4.15"
  %"str_char_5.15" = getelementptr [16 x i8], [16 x i8]* %"str_stack.15", i32 0, i32 5
  store i8 101, i8* %"str_char_5.15"
  %"str_char_6.15" = getelementptr [16 x i8], [16 x i8]* %"str_stack.15", i32 0, i32 6
  store i8 99, i8* %"str_char_6.15"
  %"str_char_7.15" = getelementptr [16 x i8], [16 x i8]* %"str_stack.15", i32 0, i32 7
  store i8 116, i8* %"str_char_7.15"
  %"str_char_8.15" = getelementptr [16 x i8], [16 x i8]* %"str_stack.15", i32 0, i32 8
  store i8 101, i8* %"str_char_8.15"
  %"str_char_9.15" = getelementptr [16 x i8], [16 x i8]* %"str_stack.15", i32 0, i32 9
  store i8 100, i8* %"str_char_9.15"
  %"str_char_10.15" = getelementptr [16 x i8], [16 x i8]* %"str_stack.15", i32 0, i32 10
  store i8 58, i8* %"str_char_10.15"
  %"str_char_11.15" = getelementptr [16 x i8], [16 x i8]* %"str_stack.15", i32 0, i32 11
  store i8 32, i8* %"str_char_11.15"
  %"str_char_12.15" = getelementptr [16 x i8], [16 x i8]* %"str_stack.15", i32 0, i32 12
  store i8 53, i8* %"str_char_12.15"
  %"str_char_13.15" = getelementptr [16 x i8], [16 x i8]* %"str_stack.15", i32 0, i32 13
  store i8 41, i8* %"str_char_13.15"
  %"str_char_14.11" = getelementptr [16 x i8], [16 x i8]* %"str_stack.15", i32 0, i32 14
  store i8 10, i8* %"str_char_14.11"
  %"str_char_15.11" = getelementptr [16 x i8], [16 x i8]* %"str_stack.15", i32 0, i32 15
  store i8 0, i8* %"str_char_15.11"
  %"arg0_to_void_ptr.11" = bitcast [16 x i8]* %"str_stack.15" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr.11")
  %"above_32bit" = alloca i64
  store i64 4294967296, i64* %"above_32bit"
  %"above_div" = alloca i64
  %"above_32bit.1" = load i64, i64* %"above_32bit"
  %".316" = sext i32 10 to i64
  %".317" = sdiv i64 %"above_32bit.1", %".316"
  store i64 %".317", i64* %"above_div"
  %"above_mod" = alloca i64
  %"above_32bit.2" = load i64, i64* %"above_32bit"
  %".319" = sext i32 10 to i64
  %".320" = srem i64 %"above_32bit.2", %".319"
  store i64 %".320", i64* %"above_mod"
  %"str_stack.16" = alloca [19 x i8]
  %"str_char_0.16" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 0
  store i8 52, i8* %"str_char_0.16"
  %"str_char_1.16" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 1
  store i8 50, i8* %"str_char_1.16"
  %"str_char_2.16" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 2
  store i8 57, i8* %"str_char_2.16"
  %"str_char_3.16" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 3
  store i8 52, i8* %"str_char_3.16"
  %"str_char_4.16" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 4
  store i8 57, i8* %"str_char_4.16"
  %"str_char_5.16" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 5
  store i8 54, i8* %"str_char_5.16"
  %"str_char_6.16" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 6
  store i8 55, i8* %"str_char_6.16"
  %"str_char_7.16" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 7
  store i8 50, i8* %"str_char_7.16"
  %"str_char_8.16" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 8
  store i8 57, i8* %"str_char_8.16"
  %"str_char_9.16" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 9
  store i8 54, i8* %"str_char_9.16"
  %"str_char_10.16" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 10
  store i8 32, i8* %"str_char_10.16"
  %"str_char_11.16" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 11
  store i8 47, i8* %"str_char_11.16"
  %"str_char_12.16" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 12
  store i8 32, i8* %"str_char_12.16"
  %"str_char_13.16" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 13
  store i8 49, i8* %"str_char_13.16"
  %"str_char_14.12" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 14
  store i8 48, i8* %"str_char_14.12"
  %"str_char_15.12" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 15
  store i8 32, i8* %"str_char_15.12"
  %"str_char_16.8" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 16
  store i8 61, i8* %"str_char_16.8"
  %"str_char_17.8" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 17
  store i8 32, i8* %"str_char_17.8"
  %"str_char_18.8" = getelementptr [19 x i8], [19 x i8]* %"str_stack.16", i32 0, i32 18
  store i8 0, i8* %"str_char_18.8"
  %"str_stack.17" = alloca [19 x i8]
  %"str_char_0.17" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 0
  store i8 52, i8* %"str_char_0.17"
  %"str_char_1.17" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 1
  store i8 50, i8* %"str_char_1.17"
  %"str_char_2.17" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 2
  store i8 57, i8* %"str_char_2.17"
  %"str_char_3.17" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 3
  store i8 52, i8* %"str_char_3.17"
  %"str_char_4.17" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 4
  store i8 57, i8* %"str_char_4.17"
  %"str_char_5.17" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 5
  store i8 54, i8* %"str_char_5.17"
  %"str_char_6.17" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 6
  store i8 55, i8* %"str_char_6.17"
  %"str_char_7.17" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 7
  store i8 50, i8* %"str_char_7.17"
  %"str_char_8.17" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 8
  store i8 57, i8* %"str_char_8.17"
  %"str_char_9.17" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 9
  store i8 54, i8* %"str_char_9.17"
  %"str_char_10.17" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 10
  store i8 32, i8* %"str_char_10.17"
  %"str_char_11.17" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 11
  store i8 47, i8* %"str_char_11.17"
  %"str_char_12.17" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 12
  store i8 32, i8* %"str_char_12.17"
  %"str_char_13.17" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 13
  store i8 49, i8* %"str_char_13.17"
  %"str_char_14.13" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 14
  store i8 48, i8* %"str_char_14.13"
  %"str_char_15.13" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 15
  store i8 32, i8* %"str_char_15.13"
  %"str_char_16.9" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 16
  store i8 61, i8* %"str_char_16.9"
  %"str_char_17.9" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 17
  store i8 32, i8* %"str_char_17.9"
  %"str_char_18.9" = getelementptr [19 x i8], [19 x i8]* %"str_stack.17", i32 0, i32 18
  store i8 0, i8* %"str_char_18.9"
  %"arg0_to_void_ptr.12" = bitcast [19 x i8]* %"str_stack.17" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr.12")
  %"above_div.1" = load i64, i64* %"above_div"
  %"arg1_to_void_ptr.4" = bitcast [32 x i8]* %"buffer" to i8*
  %".361" = call i64 @"u64str__2__u64__byte_ptr1__ret_u64"(i64 %"above_div.1", i8* %"arg1_to_void_ptr.4")
  %"arg0_to_void_ptr.13" = bitcast [32 x i8]* %"buffer" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr.13")
  %"str_stack.18" = alloca [24 x i8]
  %"str_char_0.18" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 0
  store i8 32, i8* %"str_char_0.18"
  %"str_char_1.18" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 1
  store i8 40, i8* %"str_char_1.18"
  %"str_char_2.18" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 2
  store i8 101, i8* %"str_char_2.18"
  %"str_char_3.18" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 3
  store i8 120, i8* %"str_char_3.18"
  %"str_char_4.18" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 4
  store i8 112, i8* %"str_char_4.18"
  %"str_char_5.18" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 5
  store i8 101, i8* %"str_char_5.18"
  %"str_char_6.18" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 6
  store i8 99, i8* %"str_char_6.18"
  %"str_char_7.18" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 7
  store i8 116, i8* %"str_char_7.18"
  %"str_char_8.18" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 8
  store i8 101, i8* %"str_char_8.18"
  %"str_char_9.18" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 9
  store i8 100, i8* %"str_char_9.18"
  %"str_char_10.18" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 10
  store i8 58, i8* %"str_char_10.18"
  %"str_char_11.18" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 11
  store i8 32, i8* %"str_char_11.18"
  %"str_char_12.18" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 12
  store i8 52, i8* %"str_char_12.18"
  %"str_char_13.18" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 13
  store i8 50, i8* %"str_char_13.18"
  %"str_char_14.14" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 14
  store i8 57, i8* %"str_char_14.14"
  %"str_char_15.14" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 15
  store i8 52, i8* %"str_char_15.14"
  %"str_char_16.10" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 16
  store i8 57, i8* %"str_char_16.10"
  %"str_char_17.10" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 17
  store i8 54, i8* %"str_char_17.10"
  %"str_char_18.10" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 18
  store i8 55, i8* %"str_char_18.10"
  %"str_char_19.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 19
  store i8 50, i8* %"str_char_19.2"
  %"str_char_20.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 20
  store i8 57, i8* %"str_char_20.2"
  %"str_char_21.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 21
  store i8 41, i8* %"str_char_21.2"
  %"str_char_22.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 22
  store i8 10, i8* %"str_char_22.2"
  %"str_char_23.2" = getelementptr [24 x i8], [24 x i8]* %"str_stack.18", i32 0, i32 23
  store i8 0, i8* %"str_char_23.2"
  %"str_stack.19" = alloca [24 x i8]
  %"str_char_0.19" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 0
  store i8 32, i8* %"str_char_0.19"
  %"str_char_1.19" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 1
  store i8 40, i8* %"str_char_1.19"
  %"str_char_2.19" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 2
  store i8 101, i8* %"str_char_2.19"
  %"str_char_3.19" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 3
  store i8 120, i8* %"str_char_3.19"
  %"str_char_4.19" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 4
  store i8 112, i8* %"str_char_4.19"
  %"str_char_5.19" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 5
  store i8 101, i8* %"str_char_5.19"
  %"str_char_6.19" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 6
  store i8 99, i8* %"str_char_6.19"
  %"str_char_7.19" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 7
  store i8 116, i8* %"str_char_7.19"
  %"str_char_8.19" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 8
  store i8 101, i8* %"str_char_8.19"
  %"str_char_9.19" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 9
  store i8 100, i8* %"str_char_9.19"
  %"str_char_10.19" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 10
  store i8 58, i8* %"str_char_10.19"
  %"str_char_11.19" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 11
  store i8 32, i8* %"str_char_11.19"
  %"str_char_12.19" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 12
  store i8 52, i8* %"str_char_12.19"
  %"str_char_13.19" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 13
  store i8 50, i8* %"str_char_13.19"
  %"str_char_14.15" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 14
  store i8 57, i8* %"str_char_14.15"
  %"str_char_15.15" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 15
  store i8 52, i8* %"str_char_15.15"
  %"str_char_16.11" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 16
  store i8 57, i8* %"str_char_16.11"
  %"str_char_17.11" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 17
  store i8 54, i8* %"str_char_17.11"
  %"str_char_18.11" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 18
  store i8 55, i8* %"str_char_18.11"
  %"str_char_19.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 19
  store i8 50, i8* %"str_char_19.3"
  %"str_char_20.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 20
  store i8 57, i8* %"str_char_20.3"
  %"str_char_21.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 21
  store i8 41, i8* %"str_char_21.3"
  %"str_char_22.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 22
  store i8 10, i8* %"str_char_22.3"
  %"str_char_23.3" = getelementptr [24 x i8], [24 x i8]* %"str_stack.19", i32 0, i32 23
  store i8 0, i8* %"str_char_23.3"
  %"arg0_to_void_ptr.14" = bitcast [24 x i8]* %"str_stack.19" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr.14")
  %"str_stack.20" = alloca [19 x i8]
  %"str_char_0.20" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 0
  store i8 52, i8* %"str_char_0.20"
  %"str_char_1.20" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 1
  store i8 50, i8* %"str_char_1.20"
  %"str_char_2.20" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 2
  store i8 57, i8* %"str_char_2.20"
  %"str_char_3.20" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 3
  store i8 52, i8* %"str_char_3.20"
  %"str_char_4.20" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 4
  store i8 57, i8* %"str_char_4.20"
  %"str_char_5.20" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 5
  store i8 54, i8* %"str_char_5.20"
  %"str_char_6.20" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 6
  store i8 55, i8* %"str_char_6.20"
  %"str_char_7.20" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 7
  store i8 50, i8* %"str_char_7.20"
  %"str_char_8.20" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 8
  store i8 57, i8* %"str_char_8.20"
  %"str_char_9.20" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 9
  store i8 54, i8* %"str_char_9.20"
  %"str_char_10.20" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 10
  store i8 32, i8* %"str_char_10.20"
  %"str_char_11.20" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 11
  store i8 37, i8* %"str_char_11.20"
  %"str_char_12.20" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 12
  store i8 32, i8* %"str_char_12.20"
  %"str_char_13.20" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 13
  store i8 49, i8* %"str_char_13.20"
  %"str_char_14.16" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 14
  store i8 48, i8* %"str_char_14.16"
  %"str_char_15.16" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 15
  store i8 32, i8* %"str_char_15.16"
  %"str_char_16.12" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 16
  store i8 61, i8* %"str_char_16.12"
  %"str_char_17.12" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 17
  store i8 32, i8* %"str_char_17.12"
  %"str_char_18.12" = getelementptr [19 x i8], [19 x i8]* %"str_stack.20", i32 0, i32 18
  store i8 0, i8* %"str_char_18.12"
  %"str_stack.21" = alloca [19 x i8]
  %"str_char_0.21" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 0
  store i8 52, i8* %"str_char_0.21"
  %"str_char_1.21" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 1
  store i8 50, i8* %"str_char_1.21"
  %"str_char_2.21" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 2
  store i8 57, i8* %"str_char_2.21"
  %"str_char_3.21" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 3
  store i8 52, i8* %"str_char_3.21"
  %"str_char_4.21" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 4
  store i8 57, i8* %"str_char_4.21"
  %"str_char_5.21" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 5
  store i8 54, i8* %"str_char_5.21"
  %"str_char_6.21" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 6
  store i8 55, i8* %"str_char_6.21"
  %"str_char_7.21" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 7
  store i8 50, i8* %"str_char_7.21"
  %"str_char_8.21" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 8
  store i8 57, i8* %"str_char_8.21"
  %"str_char_9.21" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 9
  store i8 54, i8* %"str_char_9.21"
  %"str_char_10.21" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 10
  store i8 32, i8* %"str_char_10.21"
  %"str_char_11.21" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 11
  store i8 37, i8* %"str_char_11.21"
  %"str_char_12.21" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 12
  store i8 32, i8* %"str_char_12.21"
  %"str_char_13.21" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 13
  store i8 49, i8* %"str_char_13.21"
  %"str_char_14.17" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 14
  store i8 48, i8* %"str_char_14.17"
  %"str_char_15.17" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 15
  store i8 32, i8* %"str_char_15.17"
  %"str_char_16.13" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 16
  store i8 61, i8* %"str_char_16.13"
  %"str_char_17.13" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 17
  store i8 32, i8* %"str_char_17.13"
  %"str_char_18.13" = getelementptr [19 x i8], [19 x i8]* %"str_stack.21", i32 0, i32 18
  store i8 0, i8* %"str_char_18.13"
  %"arg0_to_void_ptr.15" = bitcast [19 x i8]* %"str_stack.21" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr.15")
  %"above_mod.1" = load i64, i64* %"above_mod"
  %"arg1_to_void_ptr.5" = bitcast [32 x i8]* %"buffer" to i8*
  %".451" = call i64 @"u64str__2__u64__byte_ptr1__ret_u64"(i64 %"above_mod.1", i8* %"arg1_to_void_ptr.5")
  %"arg0_to_void_ptr.16" = bitcast [32 x i8]* %"buffer" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr.16")
  %"str_stack.22" = alloca [16 x i8]
  %"str_char_0.22" = getelementptr [16 x i8], [16 x i8]* %"str_stack.22", i32 0, i32 0
  store i8 32, i8* %"str_char_0.22"
  %"str_char_1.22" = getelementptr [16 x i8], [16 x i8]* %"str_stack.22", i32 0, i32 1
  store i8 40, i8* %"str_char_1.22"
  %"str_char_2.22" = getelementptr [16 x i8], [16 x i8]* %"str_stack.22", i32 0, i32 2
  store i8 101, i8* %"str_char_2.22"
  %"str_char_3.22" = getelementptr [16 x i8], [16 x i8]* %"str_stack.22", i32 0, i32 3
  store i8 120, i8* %"str_char_3.22"
  %"str_char_4.22" = getelementptr [16 x i8], [16 x i8]* %"str_stack.22", i32 0, i32 4
  store i8 112, i8* %"str_char_4.22"
  %"str_char_5.22" = getelementptr [16 x i8], [16 x i8]* %"str_stack.22", i32 0, i32 5
  store i8 101, i8* %"str_char_5.22"
  %"str_char_6.22" = getelementptr [16 x i8], [16 x i8]* %"str_stack.22", i32 0, i32 6
  store i8 99, i8* %"str_char_6.22"
  %"str_char_7.22" = getelementptr [16 x i8], [16 x i8]* %"str_stack.22", i32 0, i32 7
  store i8 116, i8* %"str_char_7.22"
  %"str_char_8.22" = getelementptr [16 x i8], [16 x i8]* %"str_stack.22", i32 0, i32 8
  store i8 101, i8* %"str_char_8.22"
  %"str_char_9.22" = getelementptr [16 x i8], [16 x i8]* %"str_stack.22", i32 0, i32 9
  store i8 100, i8* %"str_char_9.22"
  %"str_char_10.22" = getelementptr [16 x i8], [16 x i8]* %"str_stack.22", i32 0, i32 10
  store i8 58, i8* %"str_char_10.22"
  %"str_char_11.22" = getelementptr [16 x i8], [16 x i8]* %"str_stack.22", i32 0, i32 11
  store i8 32, i8* %"str_char_11.22"
  %"str_char_12.22" = getelementptr [16 x i8], [16 x i8]* %"str_stack.22", i32 0, i32 12
  store i8 54, i8* %"str_char_12.22"
  %"str_char_13.22" = getelementptr [16 x i8], [16 x i8]* %"str_stack.22", i32 0, i32 13
  store i8 41, i8* %"str_char_13.22"
  %"str_char_14.18" = getelementptr [16 x i8], [16 x i8]* %"str_stack.22", i32 0, i32 14
  store i8 10, i8* %"str_char_14.18"
  %"str_char_15.18" = getelementptr [16 x i8], [16 x i8]* %"str_stack.22", i32 0, i32 15
  store i8 0, i8* %"str_char_15.18"
  %"str_stack.23" = alloca [16 x i8]
  %"str_char_0.23" = getelementptr [16 x i8], [16 x i8]* %"str_stack.23", i32 0, i32 0
  store i8 32, i8* %"str_char_0.23"
  %"str_char_1.23" = getelementptr [16 x i8], [16 x i8]* %"str_stack.23", i32 0, i32 1
  store i8 40, i8* %"str_char_1.23"
  %"str_char_2.23" = getelementptr [16 x i8], [16 x i8]* %"str_stack.23", i32 0, i32 2
  store i8 101, i8* %"str_char_2.23"
  %"str_char_3.23" = getelementptr [16 x i8], [16 x i8]* %"str_stack.23", i32 0, i32 3
  store i8 120, i8* %"str_char_3.23"
  %"str_char_4.23" = getelementptr [16 x i8], [16 x i8]* %"str_stack.23", i32 0, i32 4
  store i8 112, i8* %"str_char_4.23"
  %"str_char_5.23" = getelementptr [16 x i8], [16 x i8]* %"str_stack.23", i32 0, i32 5
  store i8 101, i8* %"str_char_5.23"
  %"str_char_6.23" = getelementptr [16 x i8], [16 x i8]* %"str_stack.23", i32 0, i32 6
  store i8 99, i8* %"str_char_6.23"
  %"str_char_7.23" = getelementptr [16 x i8], [16 x i8]* %"str_stack.23", i32 0, i32 7
  store i8 116, i8* %"str_char_7.23"
  %"str_char_8.23" = getelementptr [16 x i8], [16 x i8]* %"str_stack.23", i32 0, i32 8
  store i8 101, i8* %"str_char_8.23"
  %"str_char_9.23" = getelementptr [16 x i8], [16 x i8]* %"str_stack.23", i32 0, i32 9
  store i8 100, i8* %"str_char_9.23"
  %"str_char_10.23" = getelementptr [16 x i8], [16 x i8]* %"str_stack.23", i32 0, i32 10
  store i8 58, i8* %"str_char_10.23"
  %"str_char_11.23" = getelementptr [16 x i8], [16 x i8]* %"str_stack.23", i32 0, i32 11
  store i8 32, i8* %"str_char_11.23"
  %"str_char_12.23" = getelementptr [16 x i8], [16 x i8]* %"str_stack.23", i32 0, i32 12
  store i8 54, i8* %"str_char_12.23"
  %"str_char_13.23" = getelementptr [16 x i8], [16 x i8]* %"str_stack.23", i32 0, i32 13
  store i8 41, i8* %"str_char_13.23"
  %"str_char_14.19" = getelementptr [16 x i8], [16 x i8]* %"str_stack.23", i32 0, i32 14
  store i8 10, i8* %"str_char_14.19"
  %"str_char_15.19" = getelementptr [16 x i8], [16 x i8]* %"str_stack.23", i32 0, i32 15
  store i8 0, i8* %"str_char_15.19"
  %"arg0_to_void_ptr.17" = bitcast [16 x i8]* %"str_stack.23" to i8*
  call void @"standard__io__console__print__1__noopstr__ret_void"(i8* %"arg0_to_void_ptr.17")
  call void @"standard__io__console__print__0__ret_void"()
  call void @"standard__io__console__print__0__ret_void"()
  ret i32 0
}
