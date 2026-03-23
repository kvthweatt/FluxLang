// redwayland.fx - Flux Wayland Client Library
// Pure Wayland window creation using only fmalloc/ffree.
// No X11, no malloc, no CRT init collisions.

#ifndef FLUX_STANDARD_TYPES
#import "redtypes.fx";
#endif;

#ifndef FLUX_STANDARD_ALLOCATORS
#import "redallocators.fx";
#endif;

#ifndef __LINUX_INTERFACE__
#import "redlinux.fx";
#endif;

#ifndef FLUX_STANDARD_NET_LINUX
#import "rednet_linux.fx";
#endif;

using standard::system::linux;
using standard::net;

#ifndef __WAYLAND_CLIENT__
#def __WAYLAND_CLIENT__ 1;

namespace standard
{
    namespace system
    {
        namespace wayland
        {
            // ================================================================
            // WAYLAND WIRE PROTOCOL
            // ================================================================

            // Every Wayland message header: object id + (size<<16 | opcode)
            struct WlMsgHeader
            {
                u32 object_id;
                u32 size_opcode;   // high 16 = total size in bytes, low 16 = opcode
            };

            // wl_display fixed object ids
            enum WlDisplayObj
            {
                WL_DISPLAY_ID = 1
            };

            // wl_display opcodes (requests)
            enum WlDisplayOp
            {
                WL_DISPLAY_SYNC         = 0,
                WL_DISPLAY_GET_REGISTRY = 1
            };

            // wl_registry event opcodes
            enum WlRegistryEv
            {
                WL_REGISTRY_GLOBAL        = 0,
                WL_REGISTRY_GLOBAL_REMOVE = 1
            };

            // wl_registry request opcodes
            enum WlRegistryOp
            {
                WL_REGISTRY_BIND = 0
            };

            // wl_compositor request opcodes
            enum WlCompositorOp
            {
                WL_COMPOSITOR_CREATE_SURFACE = 0
            };

            // wl_surface request opcodes
            enum WlSurfaceOp
            {
                WL_SURFACE_ATTACH  = 1,
                WL_SURFACE_COMMIT  = 6
            };

            // wl_shm request opcodes
            enum WlShmOp
            {
                WL_SHM_CREATE_POOL = 0
            };

            // wl_shm_pool request opcodes
            enum WlShmPoolOp
            {
                WL_SHM_POOL_CREATE_BUFFER = 0,
                WL_SHM_POOL_DESTROY       = 1
            };

            // wl_buffer request opcodes
            enum WlBufferOp
            {
                WL_BUFFER_DESTROY = 0
            };

            // xdg_wm_base request opcodes
            enum XdgWmBaseOp
            {
                XDG_WM_BASE_GET_XDG_SURFACE = 2
            };

            // xdg_surface request opcodes
            enum XdgSurfaceOp
            {
                XDG_SURFACE_GET_TOPLEVEL = 1,
                XDG_SURFACE_ACK_CONFIGURE = 4
            };

            // xdg_toplevel request opcodes
            enum XdgToplevelOp
            {
                XDG_TOPLEVEL_SET_TITLE = 2
            };

            // xdg_surface event opcodes
            enum XdgSurfaceEv
            {
                XDG_SURFACE_CONFIGURE = 0
            };

            // xdg_wm_base event opcodes
            enum XdgWmBaseEv
            {
                XDG_WM_BASE_PING = 0
            };

            // xdg_wm_base request: pong
            enum XdgWmBasePong
            {
                XDG_WM_BASE_PONG = 3
            };

            // wl_shm pixel format
            enum WlShmFormat
            {
                WL_SHM_FORMAT_ARGB8888 = 0,
                WL_SHM_FORMAT_XRGB8888 = 1
            };

            // ================================================================
            // SEND BUFFER
            // ================================================================

            // Max outgoing message buffer size
            #def WL_SEND_BUF_SIZE 4096;

            // ================================================================
            // WAYLAND WINDOW OBJECT
            // ================================================================

            object Window
            {
                int     fd;             // Wayland socket fd
                int     shm_fd;        // shared memory fd
                u32     next_id;       // next object id to allocate
                u32     registry_id,
                        compositor_id,
                        shm_id,
                        xdg_wm_base_id,
                        surface_id,
                        xdg_surface_id,
                        toplevel_id,
                        shm_pool_id,
                        buffer_id,
                        callback_id;
                u32     compositor_name,
                        shm_name,
                        xdg_wm_base_name;
                int     width,
                        height;
                u64     shm_data;      // mmap pointer to shared memory pixels
                size_t  shm_size;
                bool    configured,
                        running;

                // ============================================================
                // CONSTRUCTOR
                // ============================================================

                def __init(byte* title, int w, int h) -> this
                {
                    this.width      = w;
                    this.height     = h;
                    this.next_id    = 2;    // 1 = wl_display
                    this.configured = false;
                    this.running    = true;
                    this.shm_data   = (u64)0;
                    this.shm_size   = (size_t)0;
                    this.compositor_name    = (u32)0;
                    this.shm_name           = (u32)0;
                    this.xdg_wm_base_name   = (u32)0;

                    // Connect to Wayland compositor
                    this.fd = wl_connect();
                    if (this.fd < 0)
                    {
                        this.running = false;
                        this.shm_fd  = -1;
                        return this;
                    };

                    // Allocate object ids
                    this.registry_id    = this.alloc_id();
                    this.compositor_id  = this.alloc_id();
                    this.shm_id         = this.alloc_id();
                    this.xdg_wm_base_id = this.alloc_id();
                    this.surface_id     = this.alloc_id();
                    this.xdg_surface_id = this.alloc_id();
                    this.toplevel_id    = this.alloc_id();
                    this.shm_pool_id    = this.alloc_id();
                    this.buffer_id      = this.alloc_id();
                    this.callback_id    = this.alloc_id();

                    // Get registry
                    wl_display_get_registry(this.fd, this.registry_id);

                    // Roundtrip to receive globals
                    wl_sync_roundtrip(this.fd, this.callback_id);

                    // Read events to discover globals
                    this.read_events_until_sync();

                    // Bind compositor, shm, xdg_wm_base
                    wl_registry_bind_compositor(this.fd, this.registry_id, this.compositor_id, this.compositor_name);
                    wl_registry_bind_shm(this.fd, this.registry_id, this.shm_id, this.shm_name);
                    wl_registry_bind_xdg_wm_base(this.fd, this.registry_id, this.xdg_wm_base_id, this.xdg_wm_base_name);

                    // Create surface
                    wl_compositor_create_surface(this.fd, this.compositor_id, this.surface_id);

                    // Create xdg_surface and toplevel
                    xdg_wm_base_get_xdg_surface(this.fd, this.xdg_wm_base_id, this.xdg_surface_id, this.surface_id);
                    xdg_surface_get_toplevel(this.fd, this.xdg_surface_id, this.toplevel_id);
                    xdg_toplevel_set_title(this.fd, this.toplevel_id, title);

                    // Commit surface to trigger configure event
                    wl_surface_commit(this.fd, this.surface_id);

                    // Wait for xdg_surface configure
                    this.wait_for_configure();

                    // Create shared memory buffer
                    this.shm_size = (size_t)(w * h * 4);
                    this.shm_fd   = wl_shm_open(this.shm_size);
                    this.shm_data = mmap((u64)0, this.shm_size, 3, 1, this.shm_fd, (i64)0);

                    wl_shm_create_pool(this.fd, this.shm_id, this.shm_pool_id, this.shm_fd, (i64)this.shm_size);
                    wl_shm_pool_create_buffer(this.fd, this.shm_pool_id, this.buffer_id, 0, w, h, w * 4, WlShmFormat.WL_SHM_FORMAT_XRGB8888);

                    // Attach buffer and commit
                    wl_surface_attach(this.fd, this.surface_id, this.buffer_id);
                    wl_surface_commit(this.fd, this.surface_id);

                    return this;
                };

                // ============================================================
                // DESTRUCTOR
                // ============================================================

                def __exit() -> void
                {
                    if (this.shm_data != (u64)0)
                    {
                        munmap(this.shm_data, this.shm_size);
                    };
                    if (this.shm_fd > 0)
                    {
                        close(this.shm_fd);
                    };
                    if (this.fd > 0)
                    {
                        close(this.fd);
                    };
                    return;
                };

                // ============================================================
                // CLEAR - fill framebuffer with a packed 0x00RRGGBB color
                // ============================================================

                def clear(u32 color) -> void
                {
                    u32* pixels = (u32*)this.shm_data;
                    int  total  = this.width * this.height;
                    int  i      = 0;
                    while (i < total)
                    {
                        pixels[i] = color;
                        i++;
                    };
                    return;
                };

                // ============================================================
                // PRESENT - flush framebuffer to compositor
                // ============================================================

                def present() -> void
                {
                    wl_surface_attach(this.fd, this.surface_id, this.buffer_id);
                    wl_surface_commit(this.fd, this.surface_id);
                    return;
                };

                // ============================================================
                // PROCESS MESSAGES - pump events, returns false to quit
                // ============================================================

                def process_messages() -> bool
                {
                    return wl_pump_events(this.fd, this.xdg_wm_base_id, this.xdg_surface_id, this.callback_id);
                };

                // ============================================================
                // HELPERS
                // ============================================================

                def alloc_id() -> u32
                {
                    u32 id    = this.next_id;
                    this.next_id++;
                    return id;
                };

                def read_events_until_sync() -> void
                {
                    // Set socket non-blocking so we know when there's nothing left
                    fcntl(this.fd, 4, 2048);    // F_SETFL, O_NONBLOCK

                    // Read wl_registry.global events to discover global names
                    // wl_registry.global: obj=registry_id, op=0, payload: name(u32) iface_len(u32) iface(str) version(u32)
                    byte[4096] buf;
                    noopstr wl_compositor_str  = "wl_compositor\0";
                    noopstr wl_shm_str         = "wl_shm\0";
                    noopstr xdg_wm_base_str    = "xdg_wm_base\0";
                    int i = 0;
                    while (i < 64)
                    {
                        int got = (int)read(this.fd, (void*)buf, (size_t)4096);
                        if (got < 0)
                        {
                            // EAGAIN: nothing left to read right now
                            if (this.compositor_name != (u32)0 & this.shm_name != (u32)0 & this.xdg_wm_base_name != (u32)0)
                            {
                                break;
                            };
                            i++;
                            continue;
                        };
                        if (got > 0)
                        {
                            int offset = 0;
                            while (offset + 8 <= got)
                            {
                                u32* hdr    = (u32*)(buf + offset);
                                u32  obj    = hdr[0];
                                u32  sizeop = hdr[1];
                                u32  op     = sizeop & (u32)0xFFFF;
                                u32  msgsz  = (sizeop >> 16) & (u32)0xFFFF;

                                // wl_registry.global = op 0
                                if (obj == this.registry_id & op == (u32)0)
                                {
                                    u32*  d        = (u32*)((byte*)buf + offset + 8);
                                    u32   gname    = d[0];
                                    u32   iflen    = d[1];
                                    byte* iface    = (byte*)buf + offset + 16;
                                    if (strcmp(iface, (byte*)@wl_compositor_str) == 0)
                                    {
                                        this.compositor_name = gname;
                                    };
                                    if (strcmp(iface, (byte*)@wl_shm_str) == 0)
                                    {
                                        this.shm_name = gname;
                                    };
                                    if (strcmp(iface, (byte*)@xdg_wm_base_str) == 0)
                                    {
                                        this.xdg_wm_base_name = gname;
                                    };
                                };

                                if (msgsz < (u32)8) { break; };
                                offset = offset + (int)msgsz;
                            };
                        };
                        // Stop once we have all three
                        if (this.compositor_name != (u32)0 & this.shm_name != (u32)0 & this.xdg_wm_base_name != (u32)0)
                        {
                            break;
                        };
                        i++;
                    };

                    // Restore blocking mode
                    fcntl(this.fd, 4, 0);       // F_SETFL, 0
                    return;
                };

                def wait_for_configure() -> void
                {
                    // Read events until xdg_surface configure arrives
                    byte[4096] buf;
                    int i = 0;
                    while (i < 8 & !this.configured)
                    {
                        int got = (int)read(this.fd, (void*)buf, (size_t)4096);
                        if (got > 0)
                        {
                            // Parse configure: look for xdg_surface.configure (opcode 0)
                            int offset = 0;
                            while (offset + 8 <= got)
                            {
                                u32* hdr    = (u32*)(buf + offset);
                                u32  obj    = hdr[0];
                                u32  sizeop = hdr[1];
                                u32  op     = sizeop & (u32)0xFFFF;
                                u32  msgsz  = (sizeop >> 16) & (u32)0xFFFF;

                                if (obj == this.xdg_surface_id & op == (u32)XdgSurfaceEv.XDG_SURFACE_CONFIGURE)
                                {
                                    // ack configure with the serial
                                    u32* msg_data   = (u32*)(buf + offset + 8);
                                    u32  serial = msg_data[0];
                                    xdg_surface_ack_configure(this.fd, this.xdg_surface_id, serial);
                                    this.configured = true;
                                };

                                if (msgsz < (u32)8)
                                {
                                    break;
                                };
                                offset = offset + (int)msgsz;
                            };
                        };
                        i++;
                    };
                    return;
                };
            };

            // ================================================================
            // WAYLAND CONNECTION
            // ================================================================

            def wl_connect() -> int
            {
                noopstr path = "/mnt/wslg/runtime-dir/wayland-0\0";
                return unix_connect((byte*)@path);
            };

            // ================================================================
            // MESSAGE HELPERS
            // ================================================================

            def wl_send(int fd, u32 obj_id, u32 opcode, byte* payload, u32 payload_len) -> void
            {
                u32 total = (u32)8 + payload_len;
                byte* buf = (byte*)fmalloc((size_t)total);

                u32* hdr = (u32*)buf;
                hdr[0]   = obj_id;
                hdr[1]   = (total << 16) | (opcode & (u32)0xFFFF);

                if (payload_len > (u32)0)
                {
                    memcpy((void*)(buf + 8), (void*)payload, (size_t)payload_len);
                };

                write(fd, (void*)buf, (size_t)total);
                ffree((u64)buf);
                return;
            };

            // ================================================================
            // PROTOCOL REQUESTS
            // ================================================================

            def wl_display_get_registry(int fd, u32 registry_id) -> void
            {
                byte[4] payload;
                u32* p = (u32*)@payload;
                p[0]   = registry_id;
                wl_send(fd, (u32)WlDisplayObj.WL_DISPLAY_ID, (u32)WlDisplayOp.WL_DISPLAY_GET_REGISTRY, (byte*)@payload, (u32)4);
                return;
            };

            def wl_sync_roundtrip(int fd, u32 callback_id) -> void
            {
                byte[4] payload;
                u32* p = (u32*)@payload;
                p[0]   = callback_id;
                wl_send(fd, (u32)WlDisplayObj.WL_DISPLAY_ID, (u32)WlDisplayOp.WL_DISPLAY_SYNC, (byte*)@payload, (u32)4);
                return;
            };

            def wl_registry_bind_compositor(int fd, u32 registry_id, u32 new_id, u32 name) -> void
            {
                // bind(name, interface="wl_compositor", version=4, new_id)
                noopstr iface = "wl_compositor\0";
                u32 iface_len = (u32)14;
                u32 padded    = (iface_len + (u32)3) & (u32)0xFFFFFFFC;
                u32 total     = (u32)4 + (u32)4 + padded + (u32)4 + (u32)4;
                byte* buf     = (byte*)fmalloc((size_t)total);
                u32*  p       = (u32*)buf;
                p[0] = name;
                p[1] = iface_len;
                memcpy((void*)(buf + 8), (void*)@iface, (size_t)iface_len);
                u32* tail = (u32*)(buf + 8 + padded);
                tail[0]   = (u32)4;     // version
                tail[1]   = new_id;
                wl_send(fd, registry_id, (u32)WlRegistryOp.WL_REGISTRY_BIND, buf, total);
                ffree((u64)buf);
                return;
            };

            def wl_registry_bind_shm(int fd, u32 registry_id, u32 new_id, u32 name) -> void
            {
                noopstr iface = "wl_shm\0";
                u32 iface_len = (u32)7;
                u32 padded    = (iface_len + (u32)3) & (u32)0xFFFFFFFC;
                u32 total     = (u32)4 + (u32)4 + padded + (u32)4 + (u32)4;
                byte* buf     = (byte*)fmalloc((size_t)total);
                u32*  p       = (u32*)buf;
                p[0] = name;
                p[1] = iface_len;
                memcpy((void*)(buf + 8), (void*)@iface, (size_t)iface_len);
                u32* tail = (u32*)(buf + 8 + padded);
                tail[0]   = (u32)1;     // version
                tail[1]   = new_id;
                wl_send(fd, registry_id, (u32)WlRegistryOp.WL_REGISTRY_BIND, buf, total);
                ffree((u64)buf);
                return;
            };

            def wl_registry_bind_xdg_wm_base(int fd, u32 registry_id, u32 new_id, u32 name) -> void
            {
                noopstr iface = "xdg_wm_base\0";
                u32 iface_len = (u32)12;
                u32 padded    = (iface_len + (u32)3) & (u32)0xFFFFFFFC;
                u32 total     = (u32)4 + (u32)4 + padded + (u32)4 + (u32)4;
                byte* buf     = (byte*)fmalloc((size_t)total);
                u32*  p       = (u32*)buf;
                p[0] = name;
                p[1] = iface_len;
                memcpy((void*)(buf + 8), (void*)@iface, (size_t)iface_len);
                u32* tail = (u32*)(buf + 8 + padded);
                tail[0]   = (u32)1;     // version
                tail[1]   = new_id;
                wl_send(fd, registry_id, (u32)WlRegistryOp.WL_REGISTRY_BIND, buf, total);
                ffree((u64)buf);
                return;
            };

            def wl_compositor_create_surface(int fd, u32 compositor_id, u32 surface_id) -> void
            {
                byte[4] payload;
                u32* p = (u32*)@payload;
                p[0]   = surface_id;
                wl_send(fd, compositor_id, (u32)WlCompositorOp.WL_COMPOSITOR_CREATE_SURFACE, (byte*)@payload, (u32)4);
                return;
            };

            def xdg_wm_base_get_xdg_surface(int fd, u32 xdg_wm_base_id, u32 xdg_surface_id, u32 surface_id) -> void
            {
                byte[8] payload;
                u32* p = (u32*)@payload;
                p[0]   = xdg_surface_id;
                p[1]   = surface_id;
                wl_send(fd, xdg_wm_base_id, (u32)XdgWmBaseOp.XDG_WM_BASE_GET_XDG_SURFACE, (byte*)@payload, (u32)8);
                return;
            };

            def xdg_surface_get_toplevel(int fd, u32 xdg_surface_id, u32 toplevel_id) -> void
            {
                byte[4] payload;
                u32* p = (u32*)@payload;
                p[0]   = toplevel_id;
                wl_send(fd, xdg_surface_id, (u32)XdgSurfaceOp.XDG_SURFACE_GET_TOPLEVEL, (byte*)@payload, (u32)4);
                return;
            };

            def xdg_toplevel_set_title(int fd, u32 toplevel_id, byte* title) -> void
            {
                int tlen = standard::strings::strlen(title);
                u32 title_len = (u32)tlen + (u32)1;
                u32 padded    = (title_len + (u32)3) & (u32)0xFFFFFFFC;
                u32 total     = (u32)4 + padded;
                byte* buf     = (byte*)fmalloc((size_t)total);
                u32*  p       = (u32*)buf;
                p[0]          = title_len;
                memcpy((void*)(buf + 4), (void*)title, (size_t)tlen + (size_t)1);
                wl_send(fd, toplevel_id, (u32)XdgToplevelOp.XDG_TOPLEVEL_SET_TITLE, buf, total);
                ffree((u64)buf);
                return;
            };

            def xdg_surface_ack_configure(int fd, u32 xdg_surface_id, u32 serial) -> void
            {
                byte[4] payload;
                u32* p = (u32*)@payload;
                p[0]   = serial;
                wl_send(fd, xdg_surface_id, (u32)XdgSurfaceOp.XDG_SURFACE_ACK_CONFIGURE, (byte*)@payload, (u32)4);
                return;
            };

            def wl_surface_attach(int fd, u32 surface_id, u32 buffer_id) -> void
            {
                byte[12] payload;
                u32* p = (u32*)@payload;
                p[0]   = buffer_id;
                p[1]   = (u32)0;    // x offset
                p[2]   = (u32)0;    // y offset
                wl_send(fd, surface_id, (u32)WlSurfaceOp.WL_SURFACE_ATTACH, (byte*)@payload, (u32)12);
                return;
            };

            def wl_surface_commit(int fd, u32 surface_id) -> void
            {
                wl_send(fd, surface_id, (u32)WlSurfaceOp.WL_SURFACE_COMMIT, (byte*)0, (u32)0);
                return;
            };

            def wl_shm_open(size_t size) -> int
            {
                // Create anonymous shared memory via memfd_create
                noopstr name = "flux_wl_shm\0";
                int fd = memfd_create((byte*)@name, (u32)0);
                if (fd < 0)
                {
                    return -1;
                };
                ftruncate(fd, (i64)size);
                return fd;
            };

            def wl_shm_create_pool(int fd, u32 shm_id, u32 pool_id, int shm_fd, i64 size) -> void
            {
                // Build the Wayland message: wl_shm.create_pool
                // payload: pool_id(4) + size(4) = 8 bytes  (fd is out-of-band, not in payload)
                // total message = 8 header + 8 payload = 16 bytes
                u32   total   = (u32)16;
                byte* msg_buf = (byte*)fmalloc((size_t)total);
                u32*  hdr     = (u32*)msg_buf;
                hdr[0] = shm_id;
                hdr[1] = (total << 16) | (u32)WlShmOp.WL_SHM_CREATE_POOL;
                u32* p = (u32*)(msg_buf + 8);
                p[0]   = pool_id;
                p[1]   = (u32)size;

                // Send the message with shm_fd as SCM_RIGHTS ancillary data
                iovec iov;
                iov.iov_base = (void*)msg_buf;
                iov.iov_len  = (size_t)total;

                byte[24] cmsg_buf;
                memset((void*)@cmsg_buf, 0, (size_t)24);
                cmsghdr* cm   = (cmsghdr*)@cmsg_buf;
                cm.cmsg_len   = (size_t)20;
                cm.cmsg_level = 1;      // SOL_SOCKET
                cm.cmsg_type  = 1;      // SCM_RIGHTS
                int* fd_ptr   = (int*)(@cmsg_buf + (size_t)16);
                fd_ptr[0]     = shm_fd;

                msghdr mh;
                mh.msg_name       = (void*)0;
                mh.msg_namelen    = (u32)0;
                mh.msg_iov        = (void*)@iov;
                mh.msg_iovlen     = (size_t)1;
                mh.msg_control    = (void*)@cmsg_buf;
                mh.msg_controllen = (size_t)20;
                mh.msg_flags      = 0;

                sendmsg(fd, (void*)@mh, 0);
                ffree((u64)msg_buf);
                return;
            };

            def wl_shm_pool_create_buffer(int fd, u32 pool_id, u32 buffer_id, int offset, int w, int h, int stride, u32 format) -> void
            {
                byte[24] payload;
                u32* p = (u32*)@payload;
                p[0]   = buffer_id;
                p[1]   = (u32)offset;
                p[2]   = (u32)w;
                p[3]   = (u32)h;
                p[4]   = (u32)stride;
                p[5]   = format;
                wl_send(fd, pool_id, (u32)WlShmPoolOp.WL_SHM_POOL_CREATE_BUFFER, (byte*)@payload, (u32)24);
                return;
            };

            // ================================================================
            // EVENT PUMP
            // ================================================================

            def wl_pump_events(int fd, u32 xdg_wm_base_id, u32 xdg_surface_id, u32 callback_id) -> bool
            {
                byte[4096] buf;
                int got = (int)read(fd, (void*)buf, (size_t)4096);
                if (got <= 0)
                {
                    return true;
                };

                int offset = 0;
                while (offset + 8 <= got)
                {
                    u32* hdr    = (u32*)(buf + offset);
                    u32  obj    = hdr[0];
                    u32  sizeop = hdr[1];
                    u32  op     = sizeop & (u32)0xFFFF;
                    u32  msgsz  = (sizeop >> 16) & (u32)0xFFFF;

                    // xdg_wm_base ping -> pong
                    if (obj == xdg_wm_base_id & op == (u32)XdgWmBaseEv.XDG_WM_BASE_PING)
                    {
                        u32* msg_data   = (u32*)(buf + offset + 8);
                        u32  serial = msg_data[0];
                        byte[4] pong_payload;
                        u32* pp = (u32*)@pong_payload;
                        pp[0]   = serial;
                        wl_send(fd, xdg_wm_base_id, (u32)XdgWmBasePong.XDG_WM_BASE_PONG, (byte*)@pong_payload, (u32)4);
                    };

                    // xdg_surface configure -> ack
                    if (obj == xdg_surface_id & op == (u32)XdgSurfaceEv.XDG_SURFACE_CONFIGURE)
                    {
                        u32* msg_data   = (u32*)(buf + offset + 8);
                        u32  serial = msg_data[0];
                        xdg_surface_ack_configure(fd, xdg_surface_id, serial);
                    };

                    if (msgsz < (u32)8)
                    {
                        break;
                    };
                    offset = offset + (int)msgsz;
                };

                return true;
            };

        };
    };
};

#endif;
