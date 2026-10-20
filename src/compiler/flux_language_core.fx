// Author: Karac V. Thweatt
//
// flux_language_core.fx - the language expressed in terms of itself.
//
// Must be the very first import in fxc.fx, before any compiler component.

// The goal is to rip out as many keywords as possible from being built-in

///
data{1:1} as bool;
const bool true = 1, false = 0;

data{8:8} as char;
data{compiler.config.get("byte_width",8):compiler.config.get("byte_alignment")} as byte;

data{32:32} as uint;
signed data{32:32} as int;

data{64:64} as ulong;
signed data{64:64} as long;

operator<T: int,uint,long,ulong,float,double,char,byte,bool>(T a, T b) [and] -> T -> a & b;
operator<T: int,uint,long,ulong,float,double,char,byte,bool>(T a, T b) [band] -> T -> a `& b;
operator<T: int,uint,long,ulong,float,double,char,byte,bool>(T a, T b) [nand] -> T -> a !& b;

operator<T: int,uint,long,ulong,float,double,char,byte,bool>(T a, T b) [or] -> T -> a | b;
operator<T: int,uint,long,ulong,float,double,char,byte,bool>(T a, T b) [bor] -> T -> a `| b;
operator<T: int,uint,long,ulong,float,double,char,byte,bool>(T a, T b) [nor] -> T -> a !| b;

operator<T: int,uint,long,ulong,float,double,char,byte,bool>(T a, T b) [xor] -> T -> a ^| b;
operator<T: int,uint,long,ulong,float,double,char,byte,bool>(T a, T b) [bxor] -> T -> a `^| b;
///