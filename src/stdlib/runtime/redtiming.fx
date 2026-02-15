// redtiming.fx - Timing and sleep library for Flux
#ifndef FLUX_STANDARD
#def FLUX_STANDARD 1;
#endif;

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

#ifndef FLUX_STANDARD_SYSTEM
#import "redsys.fx";
#endif;

#ifndef FLUX_STANDARD_TIMING
#def FLUX_STANDARD_TIMING 1;

namespace standard
{
    namespace timing
    {
        // ===== TIME TYPES =====
        u64 as timestamp_us;  // Microsecond timestamp
        u64 as timestamp_ms;  // Millisecond timestamp
        u64 as timestamp_ns;  // Nanosecond timestamp
        i64 as duration_ms;   // Duration in milliseconds (can be negative)
        i64 as duration_us;   // Duration in microseconds
        i64 as duration_ns;   // Duration in nanoseconds

        // ===== OS-SPECIFIC FORWARD DECLARATIONS =====
#ifdef __WINDOWS__
        // Windows timing functions
        extern
        {
            def !!
                QueryPerformanceFrequency(i64*) -> i32,
                QueryPerformanceCounter(i64*) -> i32,
                GetTickCount64() -> u64,
                Sleep(u32) -> void;
        };
#endif; // Windows

#ifdef __LINUX__
        // Linux timing syscalls (inline asm)
        def sys_clock_gettime(i32, i64*, i64*) -> i32;
        def sys_nanosleep(i64*, i64*, i64*, i64*) -> i32;

#ifdef __ARCH_X86_64__
        def sys_clock_gettime(i32 clk_id, i64* tv_sec, i64* tv_nsec) -> i32
        {
            i32 result = 0;
            volatile asm
            {
                // clock_gettime syscall: 228 (x86_64)
                movq $$228, %rax
                movl $0, %edi           // clk_id (0 = CLOCK_REALTIME)
                movq $1, %rsi           // timespec* (tv_sec)
                syscall
                movl %eax, $2            // Store result
            } :
              : "r"(clk_id), "r"(tv_sec), "m"(result), "r"(tv_nsec)
              : "rax","rdi","rsi","rcx","r11","memory";
            return result;
        };

        def sys_nanosleep(i64* req_sec, i64* req_nsec, i64* rem_sec, i64* rem_nsec) -> i32
        {
            i32 result = 0;
            volatile asm
            {
                // nanosleep syscall: 35 (x86_64)
                movq $$35, %rax
                movq $0, %rdi           // req (timespec*)
                movq $2, %rsi           // rem (timespec*)
                syscall
                movl %eax, $3            // Store result
            } :
              : "r"(req_sec), "r"(req_nsec), "r"(rem_sec), "m"(result), "r"(rem_nsec)
              : "rax","rdi","rsi","rcx","r11","memory";
            return result;
        };
#endif; // ARCH X86_64

#ifdef __ARCH_ARM64__
        def sys_clock_gettime(i32 clk_id, i64* tv_sec, i64* tv_nsec) -> i32
        {
            i32 result = 0;
            volatile asm
            {
                // clock_gettime syscall: 113 (ARM64)
                mov x8, #113
                ldr w0, [sp]            // clk_id
                ldr x1, [sp, #8]         // tv_sec pointer
                svc #0
                str w0, [sp, #16]        // Store result
            } :
              : "r"(clk_id), "r"(tv_sec), "m"(result), "r"(tv_nsec)
              : "x0","x1","x8","memory";
            return result;
        };

        def sys_nanosleep(i64* req_sec, i64* req_nsec, i64* rem_sec, i64* rem_nsec) -> i32
        {
            i32 result = 0;
            volatile asm
            {
                // nanosleep syscall: 101 (ARM64)
                mov x8, #101
                ldr x0, [sp]            // req pointer
                ldr x1, [sp, #8]         // rem pointer
                svc #0
                str w0, [sp, #16]        // Store result
            } :
              : "r"(req_sec), "r"(req_nsec), "r"(rem_sec), "m"(result), "r"(rem_nsec)
              : "x0","x1","x8","memory";
            return result;
        };
#endif; // ARCH ARM64
#endif; // Linux

#ifdef __MACOS__
        // macOS timing functions (via syscalls)
        def sys_mach_absolute_time() -> u64;
        def sys_nanosleep(i32*, i32*) -> i32;

#ifdef __ARCH_X86_64__
        def sys_mach_absolute_time() -> u64
        {
            u64 result = 0;
            volatile asm
            {
                // mach_absolute_time is a special function, not a syscall
                // We'll use RDTSC for high-resolution timing on x86_64
                rdtsc
                shlq $$32, %rdx
                orq %rdx, %rax
                movq %rax, $0
            } :
              : "m"(result)
              : "rax","rdx","memory";
            return result;
        };
#endif; // ARCH X86_64
#endif; // macOS

        // ===== HIGH-RESOLUTION TIMER =====
        object Timer
        {
            timestamp_us start_time,elapsed;
            bool is_running;
            
            def __init() -> this
            {
                this.start_time = 0;
                this.elapsed = 0;
                this.is_running = false;
                return this;
            };
            
            def start() -> void
            {
                this.start_time = get_time_us();
                this.is_running = true;
            };
            
            def stop() -> void
            {
                if (this.is_running)
                {
                    this.elapsed += get_time_us() - this.start_time;
                    this.is_running = false;
                };
            };
            
            def reset() -> void
            {
                this.start_time = 0;
                this.elapsed = 0;
                this.is_running = false;
            };
            
            def restart() -> void
            {
                this.elapsed = 0;
                this.start_time = get_time_us();
                this.is_running = true;
            };
            
            def get_elapsed_us() -> duration_us
            {
                if (this.is_running)
                {
                    return (this.elapsed + (get_time_us() - this.start_time));
                };
                return this.elapsed;
            };
            
            def get_elapsed_ms() -> duration_ms
            {
                return (this.get_elapsed_us() / 1000);
            };
            
            def get_elapsed_ns() -> duration_ns
            {
                return (this.get_elapsed_us() * 1000);
            };
            
            def is_running() -> bool
            {
                return this.is_running;
            };
        };

        // ===== STOPWATCH (SIMPLER TIMER) =====
        object Stopwatch
        {
            timestamp_us start_time,last_lap;
            bool running;
            
            def __init() -> this
            {
                this.start_time = 0;
                this.last_lap = 0;
                this.running = false;
                return this;
            };
            
            def start() -> void
            {
                this.start_time = get_time_us();
                this.last_lap = this.start_time;
                this.running = true;
            };
            
            def lap() -> duration_us
            {
                if (!this.running)
                {
                    return (duration_us)0;
                };
                
                timestamp_us now = get_time_us();
                duration_us lap_time = (now - this.last_lap);
                this.last_lap = now;
                return lap_time;
            };
            
            def stop() -> duration_us
            {
                if (!this.running)
                {
                    return (duration_us)0;
                };
                
                duration_us total = (get_time_us() - this.start_time);
                this.running = false;
                return total;
            };
        };

        // ===== TIME GETTERS =====
        def get_time_us() -> timestamp_us
        {
            timestamp_us result = 0;
            
            switch (CURRENT_OS)
            {
#ifdef __WINDOWS__
                case (1) // Windows
                {
                    i64 counter = 0;
                    i64 frequency = 0;
                    
                    QueryPerformanceCounter(@counter);
                    QueryPerformanceFrequency(@frequency);
                    
                    // Convert to microseconds
                    result = ((counter * 1000000) / frequency);
                }
#endif; // Windows
#ifdef __LINUX__
                case (2) // Linux
                {
                    i64 tv_sec = 0;
                    i64 tv_nsec = 0;
                    
                    sys_clock_gettime(0, @tv_sec, @tv_nsec);  // CLOCK_REALTIME = 0
                    
                    result = (tv_sec * 1000000 + tv_nsec / 1000);
                }
#endif; // Linux
#ifdef __MACOS__
                case (3) // macOS
                {
                    u64 ticks = sys_mach_absolute_time();
                    // Simplified: assume 1ns per tick on modern Macs
                    result = (ticks / 1000);
                }
#endif; // macOS
                default
                {
                    return 0;
                };
            };
            
            return result;
        };

        def get_time_ms() -> timestamp_ms
        {
#ifdef __WINDOWS__
            return GetTickCount64();
#else
            return (get_time_us() / 1000);
#endif;
        };

        def get_time_ns() -> timestamp_ns
        {
            return (get_time_us() * 1000);
        };

        // ===== SLEEP FUNCTIONS =====
        def sleep_ms(u32 milliseconds) -> void
        {
            switch (CURRENT_OS)
            {
#ifdef __WINDOWS__
                case (1) // Windows
                {
                    Sleep(milliseconds);
                }
#endif; // Windows
#ifdef __LINUX__
                case (2) // Linux
                {
                    i64 req_sec = milliseconds / 1000;
                    i64 req_nsec = milliseconds % 1000) * 1000000;
                    i64 rem_sec = 0;
                    i64 rem_nsec = 0;
                    
                    sys_nanosleep(@req_sec, @req_nsec, @rem_sec, @rem_nsec);
                }
#endif; // Linux
#ifdef __MACOS__
                case (3) // macOS
                {
                    // Use syscall for nanosleep on macOS
                    // Simplified: busy wait for now
                    timestamp_ms start = get_time_ms();
                    while ((get_time_ms() - start) < milliseconds)
                    {
                        // Busy wait
                    };
                }
#endif; // macOS
                default
                {
                    return;
                };
            };
        };

        def sleep_us(u32 microseconds) -> void
        {
            if (microseconds < 1000)
            {
                // For very short sleeps, use busy wait
                timestamp_us start = get_time_us();
                while ((get_time_us() - start) < microseconds)
                {
                    // Busy wait
                };
            }
            else
            {
                // Use millisecond sleep for longer durations
                sleep_ms(microseconds / 1000);
            };
        };

        def sleep_ns(u32 nanoseconds) -> void
        {
            if (nanoseconds < 1000)
            {
                // Busy wait for very short durations
                timestamp_ns start = get_time_ns();
                while ((get_time_ns() - start) < nanoseconds)
                {
                    // Busy wait
                };
            }
            else
            {
                sleep_us(nanoseconds / 1000);
            };
        };

        def sleep_until(timestamp_us target_time) -> bool
        {
            timestamp_us now = get_time_us();
            
            if (now >= target_time)
            {
                return false;  // Already past target
            };
            
            duration_us wait_time = (target_time - now);
            sleep_us(wait_time);
            return true;
        };

        // ===== TIMEOUT TIMER =====
        object Timeout
        {
            timestamp_us start_time;
            duration_us timeout_duration;
            bool active;
            
            def __init(duration_ms timeout) -> this
            {
                this.timeout_duration = timeout * 1000;
                this.start_time = 0;
                this.active = false;
                return this;
            };
            
            def start() -> void
            {
                this.start_time = get_time_us();
                this.active = true;
            };
            
            def reset() -> void
            {
                this.start_time = get_time_us();
            };
            
            def has_expired() -> bool
            {
                if (!this.active)
                {
                    return false;
                };
                
                timestamp_us now = get_time_us();
                return (now - this.start_time) >= this.timeout_duration;
            };
            
            def remaining_us() -> duration_us
            {
                if (!this.active)
                {
                    return (duration_us)0;
                };
                
                timestamp_us now = get_time_us();
                duration_us elapsed = (now - this.start_time);
                
                if (elapsed >= this.timeout_duration)
                {
                    return (duration_us)0;
                };
                
                return this.timeout_duration - elapsed;
            };
            
            def remaining_ms() -> duration_ms
            {
                return this.remaining_us() / 1000;
            };
            
            def stop() -> void
            {
                this.active = false;
            };
        };

        // ===== PERFORMANCE COUNTER =====
        object PerformanceCounter
        {
            timestamp_us total_time;
            u32 call_count;
            timestamp_us min_time;
            timestamp_us max_time;
            bool is_recording;
            Timer current_timer;
            
            def __init() -> this
            {
                this.total_time = (timestamp_us)0;
                this.call_count = (u32)0;
                this.min_time = (timestamp_us)0xFFFFFFFFFFFFFFFF;
                this.max_time = (timestamp_us)0;
                this.is_recording = false;
                this.current_timer = Timer();
                return this;
            };
            
            def begin() -> void
            {
                if (!this.is_recording)
                {
                    this.current_timer.start();
                    this.is_recording = true;
                };
            };
            
            def end() -> bool
            {
                if (!this.is_recording)
                {
                    return false;
                };
                
                this.current_timer.stop();
                timestamp_us elapsed = this.current_timer.get_elapsed_us();
                
                this.total_time += elapsed;
                this.call_count++;
                
                if (elapsed < this.min_time)
                {
                    this.min_time = elapsed;
                };
                
                if (elapsed > this.max_time)
                {
                    this.max_time = elapsed;
                };
                
                this.is_recording = false;
                this.current_timer.reset();
                return true;
            };
            
            def reset() -> void
            {
                this.total_time = (timestamp_us)0;
                this.call_count = (u32)0;
                this.min_time = (timestamp_us)0xFFFFFFFFFFFFFFFF;
                this.max_time = (timestamp_us)0;
                this.is_recording = false;
                this.current_timer.reset();
            };
            
            def get_average_us() -> duration_us
            {
                if (this.call_count == (u32)0)
                {
                    return 0;
                };
                return (this.total_time / this.call_count);
            };
            
            def get_average_ms() -> duration_ms
            {
                return this.get_average_us() / 1000;
            };
            
            def get_min_us() -> duration_us
            {
                return this.min_time;
            };
            
            def get_max_us() -> duration_us
            {
                return this.max_time;
            };
            
            def get_call_count() -> u32
            {
                return this.call_count;
            };
            
            def get_total_us() -> duration_us
            {
                return this.total_time;
            };
        };

        // ===== DATE AND TIME STRUCTURES =====
        struct DateTime
        {
            i16 year;
            i8 month;    // 1-12
            i8 day;      // 1-31
            i8 hour;     // 0-23
            i8 minute;   // 0-59
            i8 second;   // 0-59
            i16 millisecond;
        };

        // ===== SYSTEM TIME =====
#ifdef __WINDOWS__
        extern
        {
            def !!
                GetSystemTime(i16* lpSystemTime) -> void,
                GetLocalTime(i16* lpSystemTime) -> void;
        };
#endif; // Windows

        def get_system_time() -> DateTime
        {
            DateTime result = {
                year = 1970,
                month = 1,
                day = 1,
                hour = 0,
                minute = 0,
                second = 0,
                millisecond = 0
            };
            
#ifdef __WINDOWS__
            i16 system_time[8];  // year, month, day, hour, minute, second, milliseconds, dayofweek
            GetLocalTime(@system_time[0]);
            
            result.year = system_time[0];
            result.month = system_time[1];
            result.day = system_time[3];  // day is at index 3
            result.hour = system_time[4];
            result.minute = system_time[5];
            result.second = system_time[6];
            result.millisecond = system_time[7];
#else
            // On Linux/macOS, we'd need to call gettimeofday or similar
            // For now, return epoch
#endif; // Windows
            
            return result;
        };

        // ===== TIME FORMATTING =====
        def format_time(duration_ms ms, byte* buffer, size_t buffer_size) -> void
        {
            if (buffer_size < 32)
            {
                return;
            };
            
            i64 abs_ms = ms;
            bool negative = false;
            
            if (ms < (duration_ms)0)
            {
                negative = true;
                abs_ms = -abs_ms;
            };

            i64 hours,
                minutes,
                seconds,
                millis
            =
                abs_ms / (i64)3600000,
                (abs_ms % (i64)3600000) / (i64)60000,
                (abs_ms % (i64)60000) / (i64)1000,
                abs_ms % (i64)1000;
            
            i32 pos = 0;
            
            if (negative)
            {
                buffer[pos] = (byte)'-';
                pos++;
            };
            
            // Format HH:MM:SS.mmm
            if (hours < (i64)10)
            {
                buffer[pos] = (byte)'0';
                pos++;
                buffer[pos] = (byte)((i32)'0' + (i32)hours);
                pos++;
            }
            else
            {
                buffer[pos] = (byte)((i32)'0' + (i32)(hours / (i64)10));
                pos++;
                buffer[pos] = (byte)((i32)'0' + (i32)(hours % (i64)10));
                pos++;
            };
            
            buffer[pos] = (byte)':';
            pos++;
            
            buffer[pos] = (byte)((i32)'0' + (i32)(minutes / (i64)10));
            pos++;
            buffer[pos] = (byte)((i32)'0' + (i32)(minutes % (i64)10));
            pos++;
            
            buffer[pos] = (byte)':';
            pos++;
            
            buffer[pos] = (byte)((i32)'0' + (i32)(seconds / (i64)10));
            pos++;
            buffer[pos] = (byte)((i32)'0' + (i32)(seconds % (i64)10));
            pos++;
            
            buffer[pos] = (byte)'.';
            pos++;
            
            buffer[pos] = (byte)((i32)'0' + (i32)(millis / (i64)100));
            pos++;
            buffer[pos] = (byte)((i32)'0' + (i32)((millis % (i64)100) / (i64)10));
            pos++;
            buffer[pos] = (byte)((i32)'0' + (i32)(millis % (i64)10));
            pos++;
            
            buffer[pos] = '\0';
        };

        // ===== UTILITY FUNCTIONS =====
        def seconds_to_ms(float seconds) -> duration_ms
        {
            return (duration_ms)(seconds * 1000.0);
        };

        def minutes_to_ms(float minutes) -> duration_ms
        {
            return (duration_ms)(minutes * 60000.0);
        };

        def hours_to_ms(float hours) -> duration_ms
        {
            return (duration_ms)(hours * 3600000.0);
        };

        def ms_to_seconds(duration_ms ms) -> float
        {
            return ms / 1000.0;
        };

        def ms_to_minutes(duration_ms ms) -> float
        {
            return ms / 60000.0;
        };

        def ms_to_hours(duration_ms ms) -> float
        {
            return ms / 3600000.0;
        };

        // ===== PRECISION SLEEP WITH BUSY WAIT =====
        def busy_wait_us(u32 microseconds) -> void
        {
            timestamp_us start = get_time_us();
            while ((get_time_us() - start) < (timestamp_us)microseconds)
            {
                // Busy wait
            };
        };

        def spin_until(timestamp_us target_time) -> void
        {
            while (get_time_us() < target_time)
            {
                // Do nothing
            };
        };

        // ===== TICK COUNTER =====
        object TickCounter
        {
            u64 ticks;
            timestamp_us last_tick_time;
            float ticks_per_second;
            
            def __init(float target_hz) -> this
            {
                this.ticks = (u64)0;
                this.last_tick_time = get_time_us();
                this.ticks_per_second = target_hz;
                return this;
            };
            
            def wait_for_tick() -> bool
            {
                timestamp_us now = get_time_us();
                duration_us target_interval = (duration_us)(1000000.0 / this.ticks_per_second);
                duration_us elapsed = (duration_us)(now - this.last_tick_time);
                
                if (elapsed < target_interval)
                {
                    sleep_us((u32)(target_interval - elapsed));
                };
                
                this.last_tick_time = get_time_us();
                this.ticks++;
                return true;
            };
            
            def get_tick_count() -> u64
            {
                return this.ticks;
            };
            
            def get_actual_hz() -> float
            {
                timestamp_us now = get_time_us();
                duration_us elapsed = (duration_us)(now - this.last_tick_time);
                
                if (elapsed == (duration_us)0)
                {
                    return 0.0;
                };
                
                return 1000000.0 / elapsed;
            };
        };
    };
};

using standard::timing;

#endif; // FLUX_STANDARD_TIMING