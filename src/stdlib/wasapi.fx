// Author: Karac V. Thweatt
// wasapi.fx - WASAPI loopback audio capture
// Captures system audio output as PCM float32 samples via COM vtable calls.
// No C++ headers required - vtable offsets are fixed by the Windows ABI.

#ifndef FLUX_WASAPI
#def FLUX_WASAPI 1;
#endif;

#ifndef FLUX_STANDARD_TYPES
#import "types.fx";
#endif;

#ifndef __WIN32_INTERFACE__
#import "windows.fx";
#endif;

using standard::system::windows;

// ============================================================================
// COM / WASAPI extern declarations
// ============================================================================

// ============================================================================
// WASAPI constants
// ============================================================================

#def COINIT_MULTITHREADED     0u;
#def COINIT_APARTMENTTHREADED 0x2u;
#def CLSCTX_ALL               0x17u;
#def CLSCTX_INPROC_SERVER     0x1u;
#def eRender                  0u;
#def eCapture                 1u;
#def eConsole                 0u;
#def AUDCLNT_SHAREMODE_SHARED         0u;
#def AUDCLNT_SHAREMODE_EXCLUSIVE      1u;
#def AUDCLNT_STREAMFLAGS_LOOPBACK     0x00020000u;
#def AUDCLNT_STREAMFLAGS_EVENTCALLBACK 0x00040000u;
#def WAVE_FORMAT_PCM        1;
#def WAVE_FORMAT_IEEE_FLOAT 3;
#def WAVE_FORMAT_EXTENSIBLE 0xFFFE;
#def S_OK                   0;


extern
{
    def !!
        CoInitializeEx(void*, u32)    -> HRESULT,
        CoUninitialize()              -> void,
        CoCreateInstance(void*, void*, u32, void*, void**) -> HRESULT;
};

// ============================================================================
// GUIDs
// ============================================================================

struct GUID
{
    u32 data1;
    u16 data2,
        data3;
    byte[8] data4;
};

// CLSID_MMDeviceEnumerator = {BCDE0395-E52F-467C-8E3D-C4579291692E}
global GUID CLSID_MMDeviceEnumerator;

// IID_IMMDeviceEnumerator = {A95664D2-9614-4F35-A746-DE8DB63617E6}
global GUID IID_IMMDeviceEnumerator;

// IID_IAudioClient = {1CB9AD4C-DBFA-4C32-B178-C2F568A703B2}
global GUID IID_IAudioClient;

// IID_IAudioCaptureClient = {C8ADBD64-E71E-48A0-A4DE-185C395CD317}
global GUID IID_IAudioCaptureClient;

def wasapi_init_guids() -> void
{
    // CLSID_MMDeviceEnumerator
    CLSID_MMDeviceEnumerator.data1    = 0xBCDE0395u;
    CLSID_MMDeviceEnumerator.data2    = (u16)0xE52F;
    CLSID_MMDeviceEnumerator.data3    = (u16)0x467C;
    CLSID_MMDeviceEnumerator.data4[0] = (byte)0x8E;
    CLSID_MMDeviceEnumerator.data4[1] = (byte)0x3D;
    CLSID_MMDeviceEnumerator.data4[2] = (byte)0xC4;
    CLSID_MMDeviceEnumerator.data4[3] = (byte)0x57;
    CLSID_MMDeviceEnumerator.data4[4] = (byte)0x92;
    CLSID_MMDeviceEnumerator.data4[5] = (byte)0x91;
    CLSID_MMDeviceEnumerator.data4[6] = (byte)0x69;
    CLSID_MMDeviceEnumerator.data4[7] = (byte)0x2E;

    // IID_IMMDeviceEnumerator
    IID_IMMDeviceEnumerator.data1    = 0xA95664D2u;
    IID_IMMDeviceEnumerator.data2    = (u16)0x9614;
    IID_IMMDeviceEnumerator.data3    = (u16)0x4F35;
    IID_IMMDeviceEnumerator.data4[0] = (byte)0xA7;
    IID_IMMDeviceEnumerator.data4[1] = (byte)0x46;
    IID_IMMDeviceEnumerator.data4[2] = (byte)0xDE;
    IID_IMMDeviceEnumerator.data4[3] = (byte)0x8D;
    IID_IMMDeviceEnumerator.data4[4] = (byte)0xB6;
    IID_IMMDeviceEnumerator.data4[5] = (byte)0x36;
    IID_IMMDeviceEnumerator.data4[6] = (byte)0x17;
    IID_IMMDeviceEnumerator.data4[7] = (byte)0xE6;

    // IID_IAudioClient
    IID_IAudioClient.data1    = 0x1CB9AD4Cu;
    IID_IAudioClient.data2    = (u16)0xDBFA;
    IID_IAudioClient.data3    = (u16)0x4C32;
    IID_IAudioClient.data4[0] = (byte)0xB1;
    IID_IAudioClient.data4[1] = (byte)0x78;
    IID_IAudioClient.data4[2] = (byte)0xC2;
    IID_IAudioClient.data4[3] = (byte)0xF5;
    IID_IAudioClient.data4[4] = (byte)0x68;
    IID_IAudioClient.data4[5] = (byte)0xA7;
    IID_IAudioClient.data4[6] = (byte)0x03;
    IID_IAudioClient.data4[7] = (byte)0xB2;

    // IID_IAudioCaptureClient
    IID_IAudioCaptureClient.data1    = 0xC8ADBD64u;
    IID_IAudioCaptureClient.data2    = (u16)0xE71E;
    IID_IAudioCaptureClient.data3    = (u16)0x48A0;
    IID_IAudioCaptureClient.data4[0] = (byte)0xA4;
    IID_IAudioCaptureClient.data4[1] = (byte)0xDE;
    IID_IAudioCaptureClient.data4[2] = (byte)0x18;
    IID_IAudioCaptureClient.data4[3] = (byte)0x5C;
    IID_IAudioCaptureClient.data4[4] = (byte)0x39;
    IID_IAudioCaptureClient.data4[5] = (byte)0x5C;
    IID_IAudioCaptureClient.data4[6] = (byte)0xD3;
    IID_IAudioCaptureClient.data4[7] = (byte)0x17;

    return;
};

// ============================================================================
// WAVEFORMATEX
// ============================================================================

struct WAVEFORMATEX
{
    u16   wFormatTag,
          nChannels;
    u32   nSamplesPerSec,
          nAvgBytesPerSec;
    u16   nBlockAlign,
          wBitsPerSample,
          cbSize;
};

struct WAVEFORMATEXTENSIBLE
{
    WAVEFORMATEX  Format;
    u16           wValidBitsPerSample;
    u32           dwChannelMask;
    u32           SubFormat_data1;
    u16           SubFormat_data2,
                  SubFormat_data3;
    byte[8]       SubFormat_data4;
};

// ============================================================================
// WASAPI constants
// ============================================================================

#def COINIT_MULTITHREADED     0u;
#def COINIT_APARTMENTTHREADED 0x2u;
#def CLSCTX_ALL               0x17u;
#def CLSCTX_INPROC_SERVER     0x1u;
#def eRender                  0u;
#def eCapture                 1u;
#def eConsole                 0u;
#def AUDCLNT_SHAREMODE_SHARED         0u;
#def AUDCLNT_SHAREMODE_EXCLUSIVE      1u;
#def AUDCLNT_STREAMFLAGS_LOOPBACK     0x00020000u;
#def AUDCLNT_STREAMFLAGS_EVENTCALLBACK 0x00040000u;
#def WAVE_FORMAT_PCM        1;
#def WAVE_FORMAT_IEEE_FLOAT 3;
#def WAVE_FORMAT_EXTENSIBLE 0xFFFE;
#def S_OK                   0;

// ============================================================================
// COM vtable helpers
// ============================================================================

def vtable_get(void* iface, u32 slot) -> void*
{
    // Read vtable pointer: iface points to vtable pointer (first field of COM object)
    u64* iface_as_u64ptr = (u64*)iface;
    u64  vtbl_addr       = iface_as_u64ptr[0];
    // Index into vtable: each slot is one pointer (8 bytes)
    u64* vtbl            = (u64*)(byte*)vtbl_addr;
    u64  fn_addr         = vtbl[slot];
    return (void*)(byte*)fn_addr;
};

def com_release(void* iface) -> u32
{
    def{}* fn(void*) -> u32;
    fn = vtable_get(iface, 2);
    return fn(iface);
};

def imm_GetDefaultAudioEndpoint(void* enumerator, u32 dataFlow, u32 role, void** ppDevice) -> HRESULT
{
    def{}* fn(void*, u32, u32, void**) -> HRESULT;
    fn = vtable_get(enumerator, 4);
    return fn(enumerator, dataFlow, role, ppDevice);
};

def imm_device_Activate(void* device, void* iid, u32 clsctx, void* params, void** ppInterface) -> HRESULT
{
    def{}* fn(void*, void*, u32, void*, void**) -> HRESULT;
    fn = vtable_get(device, 3);
    return fn(device, iid, clsctx, params, ppInterface);
};

def iaudio_GetMixFormat(void* client, void** ppFormat) -> HRESULT
{
    def{}* fn(void*, void**) -> HRESULT;
    fn = vtable_get(client, 8);
    return fn(client, ppFormat);
};

def iaudio_Initialize(void* client, u32 shareMode, u32 streamFlags,
                      i64 bufferDuration, i64 periodicity,
                      void* pFormat, void* sessionGuid) -> HRESULT
{
    def{}* fn(void*, u32, u32, i64, i64, void*, void*) -> HRESULT;
    fn = vtable_get(client, 3);
    return fn(client, shareMode, streamFlags, bufferDuration, periodicity, pFormat, sessionGuid);
};

def iaudio_Start(void* client) -> HRESULT
{
    def{}* fn(void*) -> HRESULT;
    fn = vtable_get(client, 10);
    return fn(client);
};

def iaudio_Stop(void* client) -> HRESULT
{
    def{}* fn(void*) -> HRESULT;
    fn = vtable_get(client, 11);
    return fn(client);
};

def iaudio_GetService(void* client, void* iid, void** ppv) -> HRESULT
{
    def{}* fn(void*, void*, void**) -> HRESULT;
    fn = vtable_get(client, 14);
    return fn(client, iid, ppv);
};

def icapture_GetBuffer(void* capture, byte** ppData, u32* pFrames,
                       u32* pdwFlags, u64* pDevPos, u64* pQPCPos) -> HRESULT
{
    def{}* fn(void*, byte**, u32*, u32*, u64*, u64*) -> HRESULT;
    fn = vtable_get(capture, 3);
    return fn(capture, ppData, pFrames, pdwFlags, pDevPos, pQPCPos);
};

def icapture_ReleaseBuffer(void* capture, u32 numFrames) -> HRESULT
{
    def{}* fn(void*, u32) -> HRESULT;
    fn = vtable_get(capture, 4);
    return fn(capture, numFrames);
};

def icapture_GetNextPacketSize(void* capture, u32* pFrames) -> HRESULT
{
    def{}* fn(void*, u32*) -> HRESULT;
    fn = vtable_get(capture, 5);
    return fn(capture, pFrames);
};

// ============================================================================
// WasapiCapture
// ============================================================================

struct WasapiCapture
{
    void*  enumerator;
    void*  device;
    void*  audio_client;
    void*  capture_client;
    u32    channels;
    u32    sample_rate;
    u32    bits_per_sample;
    bool   is_float;
    bool   ready;
};

global HRESULT g_wasapi_last_hr = 0;
global HRESULT g_wasapi_read_hr = 0;

def wasapi_open(WasapiCapture* ctx) -> bool
{
    HRESULT hr;
    u64     enumerator,
            device,
            audio_client,
            capture_client,
            mix_format_ptr;
    WAVEFORMATEX* fmt;

    wasapi_init_guids();

    hr = CoInitializeEx((void*)0, COINIT_APARTMENTTHREADED);
    // RPC_E_CHANGED_MODE (0x80010106) is acceptable - COM already initialized
    if (hr != (HRESULT)S_OK & hr != (HRESULT)0x80010106) { g_wasapi_last_hr = hr; return false; };

    hr = CoCreateInstance(
        (void*)@CLSID_MMDeviceEnumerator,
        (void*)0,
        CLSCTX_INPROC_SERVER,
        (void*)@IID_IMMDeviceEnumerator,
        (void**)@enumerator
    );
    if (hr != (HRESULT)S_OK) { g_wasapi_last_hr = hr; CoUninitialize(); return false; };

    hr = imm_GetDefaultAudioEndpoint((void*)(byte*)enumerator, eRender, eConsole, (void**)@device);
    if (hr != (HRESULT)S_OK) { g_wasapi_last_hr = hr; com_release((void*)(byte*)enumerator); CoUninitialize(); return false; };

    hr = imm_device_Activate((void*)(byte*)device, (void*)@IID_IAudioClient, CLSCTX_ALL,
                             (void*)0, (void**)@audio_client);
    if (hr != (HRESULT)S_OK)
    {
        g_wasapi_last_hr = hr;
        com_release((void*)(byte*)device);
        com_release((void*)(byte*)enumerator);
        CoUninitialize();
        return false;
    };

    hr = iaudio_GetMixFormat((void*)(byte*)audio_client, (void**)@mix_format_ptr);
    if (hr != (HRESULT)S_OK)
    {
        g_wasapi_last_hr = hr;
        com_release((void*)(byte*)audio_client);
        com_release((void*)(byte*)device);
        com_release((void*)(byte*)enumerator);
        CoUninitialize();
        return false;
    };

    fmt = (WAVEFORMATEX*)(byte*)mix_format_ptr;
    ctx.channels        = (u32)fmt.nChannels;
    ctx.sample_rate     = fmt.nSamplesPerSec;
    ctx.bits_per_sample = (u32)fmt.wBitsPerSample;
    ctx.is_float        = (fmt.wFormatTag == (u16)WAVE_FORMAT_IEEE_FLOAT)
                        | (fmt.wFormatTag == (u16)WAVE_FORMAT_EXTENSIBLE);

    // Initialize in shared loopback mode, 50ms buffer
    hr = iaudio_Initialize(
        (void*)(byte*)audio_client,
        AUDCLNT_SHAREMODE_SHARED,
        AUDCLNT_STREAMFLAGS_LOOPBACK,
        500000,
        0,
        (void*)(byte*)mix_format_ptr,
        (void*)(byte*)0
    );
    if (hr != (HRESULT)S_OK)
    {
        g_wasapi_last_hr = hr;
        com_release((void*)(byte*)audio_client);
        com_release((void*)(byte*)device);
        com_release((void*)(byte*)enumerator);
        CoUninitialize();
        return false;
    };

    hr = iaudio_GetService((void*)(byte*)audio_client, (void*)@IID_IAudioCaptureClient, (void**)@capture_client);
    if (hr != (HRESULT)S_OK)
    {
        g_wasapi_last_hr = hr;
        com_release((void*)(byte*)audio_client);
        com_release((void*)(byte*)device);
        com_release((void*)(byte*)enumerator);
        CoUninitialize();
        return false;
    };

    hr = iaudio_Start((void*)(byte*)audio_client);
    if (hr != (HRESULT)S_OK)
    {
        g_wasapi_last_hr = hr;
        com_release((void*)(byte*)capture_client);
        com_release((void*)(byte*)audio_client);
        com_release((void*)(byte*)device);
        com_release((void*)(byte*)enumerator);
        CoUninitialize();
        return false;
    };

    ctx.enumerator     = (void*)(byte*)enumerator;
    ctx.device         = (void*)(byte*)device;
    ctx.audio_client   = (void*)(byte*)audio_client;
    ctx.capture_client = (void*)(byte*)capture_client;
    ctx.ready          = true;

    return true;
};

def wasapi_close(WasapiCapture* ctx) -> void
{
    if (!ctx.ready) { return; };
    iaudio_Stop(ctx.audio_client);
    com_release(ctx.capture_client);
    com_release(ctx.audio_client);
    com_release(ctx.device);
    com_release(ctx.enumerator);
    CoUninitialize();
    ctx.ready = false;
    return;
};

def wasapi_read_samples(WasapiCapture* ctx, float* out_buf, u32 max_frames) -> u32
{
    u32    packet_frames,
           frames_written,
           flags,
           f,
           ch;
    u64    dev_pos,
           qpc_pos;
    u64    data_ptr;
    float* fdata;
    float  sample,
           inv_channels;
    HRESULT hr;

    frames_written = 0u;
    inv_channels   = 1.0f / (float)ctx.channels;

    hr = icapture_GetNextPacketSize(ctx.capture_client, @packet_frames);
    g_wasapi_read_hr = hr;
    while (hr == (HRESULT)S_OK)
    {
        if (packet_frames == 0u) { break; };
        if (frames_written >= max_frames) { break; };
        hr = icapture_GetBuffer(ctx.capture_client, (byte**)@data_ptr, @packet_frames,
                                @flags, @dev_pos, @qpc_pos);
        if (hr != (HRESULT)S_OK) { break; };

        fdata = (float*)(byte*)data_ptr;

        for (f = 0u; f < packet_frames; f++)
        {
            if (frames_written >= max_frames) { break; };
            sample = 0.0f;
            for (ch = 0u; ch < ctx.channels; ch++)
            {
                sample = sample + fdata[f * ctx.channels + ch];
            };
            out_buf[frames_written] = sample * inv_channels;
            frames_written++;
        };

        icapture_ReleaseBuffer(ctx.capture_client, packet_frames);
        hr = icapture_GetNextPacketSize(ctx.capture_client, @packet_frames);
    };

    return frames_written;
};
