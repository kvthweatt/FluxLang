#import "standard.fx", "redmath.fx", "redwindows.fx", "vulkan.fx";

using standard::io::console;
using standard::system::windows;
using standard::math;

// ============================================================================
// Mandelbrot Set - Vulkan Viewer
// W = zoom in, S = zoom out, A/D = pan X, Up/Down = pan Y
// ============================================================================

const int WIN_W        = 900,
          WIN_H        = 900,
          MAX_ITER     = 1024,
          TILE_STILL   = 1,   // Tile size when stationary
          TILE_MOVING  = 4,   // Tile size while a key is held - faster pan/zoom

// Virtual key codes
          VK_W    = 0x57,
          VK_S    = 0x53,
          VK_A    = 0x41,
          VK_D    = 0x44,
          VK_UP   = 0x26,
          VK_DOWN = 0x28;

// Compute Mandelbrot iteration count using native double precision
def mandelbrot(double x0, double y0, int max_iter) -> int
{
    double x, y, xx, yy, xtemp, cx, cy, q;
    int iter;

    // Cardioid and period-2 bulb check
    // Points inside either region are guaranteed to never escape - skip iteration entirely
    cx = x0 - 0.25;
    cy = y0;
    q  = cx * cx + cy * cy;
    // Main cardioid: q*(q + cx) < cy*cy*0.25
    if (q * (q + cx) < cy * cy * 0.25) { return max_iter; };
    // Period-2 bulb: (x+1)^2 + y^2 < 1/16
    cx = x0 + 1.0;
    if (cx * cx + cy * cy < 0.0625) { return max_iter; };

    x    = 0.0;
    y    = 0.0;
    iter = 0;

    while (iter < max_iter)
    {
        xx = x * x;
        yy = y * y;
        if (xx + yy > 4.0) { return iter; };
        xtemp = xx - yy + x0;
        y     = 2.0 * x * y + y0;
        x     = xtemp;
        iter++;
    };

    return iter;
};

// Map iteration count to an RGB color using a smooth palette
def iter_to_color(int iter, int max_iter, double* r, double* g, double* b) -> void
{
    double t, s;

    if (iter == max_iter)
    {
        // Inside the set - black
        *r = 0.0;
        *g = 0.0;
        *b = 0.0;
        return;
    };

    // t in [0,1] across one 256-step cycle - always positive
    t = (double)(iter % 256) / 255.0;

    // 5-stop palette for deep contrast:
    // 0.00 - 0.20: black -> deep purple
    // 0.20 - 0.45: deep purple -> electric blue
    // 0.45 - 0.65: electric blue -> bright teal/cyan
    // 0.65 - 0.85: bright teal -> deep gold
    // 0.85 - 1.00: deep gold -> crimson red
    if (t < 0.2)
    {
        s = t / 0.2;
        *r = s * 0.45;
        *g = 0.0;
        *b = s * 0.6;
    }
    elif (t < 0.45)
    {
        s = (t - 0.2) / 0.25;
        *r = 0.45 - s * 0.45;
        *g = s * 0.05;
        *b = 0.6 + s * 0.4;
    }
    elif (t < 0.65)
    {
        s = (t - 0.45) / 0.2;
        *r = s * 0.05;
        *g = s * 0.9;
        *b = 1.0;
    }
    elif (t < 0.85)
    {
        s = (t - 0.65) / 0.2;
        *r = 0.05 + s * 0.85;
        *g = 0.9 - s * 0.5;
        *b = 1.0 - s * 1.0;
    }
    else
    {
        s = (t - 0.85) / 0.15;
        *r = 0.9 + s * 0.1;
        *g = 0.4 - s * 0.4;
        *b = 0.0;
    };

    return;
};

extern def !!GetTickCount() -> DWORD;

// ============================================================================
// VkImageCopy region struct (not in vulkan.fx core, defined inline here)
// Each field is exactly as the Vulkan spec requires for vkCmdCopyImage.
// ============================================================================
struct VkImageCopyRegion
{
    // srcSubresource: VkImageSubresourceLayers
    u32 src_aspectMask;
    u32 src_mipLevel;
    u32 src_baseArrayLayer;
    u32 src_layerCount;
    // srcOffset: VkOffset3D
    i32 src_x, src_y, src_z;
    // dstSubresource: VkImageSubresourceLayers
    u32 dst_aspectMask;
    u32 dst_mipLevel;
    u32 dst_baseArrayLayer;
    u32 dst_layerCount;
    // dstOffset: VkOffset3D
    i32 dst_x, dst_y, dst_z;
    // extent: VkExtent3D
    u32 ext_w, ext_h, ext_d;
};

def main() -> int
{
    // Load Vulkan
    void* vk_dll;
    vk_dll = windows::vk_load();
    if (vk_dll == STDLIB_GVP) { return 1; };

    Window win("Mandelbrot Set - Vulkan  W/S: Zoom  A/D: Pan X  Up/Down: Pan Y\0",
               100, 100, WIN_W, WIN_H);

    VkContext vkctx(win.handle, win.instance, (u32)WIN_W, (u32)WIN_H);

    u32 img_w, img_h;
    img_w = vkctx.swapchain_extent.width;
    img_h = vkctx.swapchain_extent.height;

    // ---- Create a host-visible linear image for CPU pixel writes ----
    VkImage        cpu_image;
    VkDeviceMemory cpu_memory;

    VkImageCreateInfo img_ci;
    img_ci.sType                 = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    img_ci.pNext                 = STDLIB_GVP;
    img_ci.flags                 = 0;
    img_ci.imageType             = VK_IMAGE_TYPE_2D;
    img_ci.format                = vkctx.swapchain_format;
    img_ci.extent_w              = img_w;
    img_ci.extent_h              = img_h;
    img_ci.extent_d              = 1;
    img_ci.mipLevels             = 1;
    img_ci.arrayLayers           = 1;
    img_ci.samples               = (u32)VK_SAMPLE_COUNT_1_BIT;
    img_ci.tiling                = VK_IMAGE_TILING_LINEAR;
    img_ci.usage                 = (u32)VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    img_ci.sharingMode           = VK_SHARING_MODE_EXCLUSIVE;
    img_ci.queueFamilyIndexCount = 0;
    img_ci.pQueueFamilyIndices   = STDLIB_GVP;
    img_ci.initialLayout         = VK_IMAGE_LAYOUT_PREINITIALIZED;
    vkCreateImage(vkctx.device, @img_ci, STDLIB_GVP, @cpu_image);

    VkMemoryRequirements mem_req;
    vkGetImageMemoryRequirements(vkctx.device, cpu_image, @mem_req);

    VkPhysicalDeviceMemoryProperties mem_props;
    vkGetPhysicalDeviceMemoryProperties(vkctx.physical_device, @mem_props);

    u32 mem_type;
    mem_type = windows::vk_find_memory_type(@mem_props,
                   mem_req.memoryTypeBits,
                   (u32)VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                   (u32)VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);

    VkMemoryAllocateInfo alloc_info;
    alloc_info.sType           = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    alloc_info.pNext           = STDLIB_GVP;
    alloc_info.allocationSize  = mem_req.size;
    alloc_info.memoryTypeIndex = mem_type;
    alloc_info._pad            = 0;
    vkAllocateMemory(vkctx.device, @alloc_info, STDLIB_GVP, @cpu_memory);
    vkBindImageMemory(vkctx.device, cpu_image, cpu_memory, 0);

    // ---- Command pool + buffer ----
    VkCommandPool cmd_pool;

    VkCommandPoolCreateInfo pool_ci;
    pool_ci.sType            = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    pool_ci.pNext            = STDLIB_GVP;
    pool_ci.flags            = 0;
    pool_ci.queueFamilyIndex = vkctx.graphics_family;
    vkCreateCommandPool(vkctx.device, @pool_ci, STDLIB_GVP, @cmd_pool);

    VkCommandBuffer cmd_buf;

    VkCommandBufferAllocateInfo cb_ai;
    cb_ai.sType              = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cb_ai.pNext              = STDLIB_GVP;
    cb_ai.commandPool        = cmd_pool;
    cb_ai.level              = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cb_ai.commandBufferCount = 1;
    vkAllocateCommandBuffers(vkctx.device, @cb_ai, @cmd_buf);

    // ---- Semaphores and fence ----
    VkSemaphore image_avail_sem, render_done_sem;
    VkFence     frame_fence;

    VkSemaphoreCreateInfo sem_ci;
    sem_ci.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    sem_ci.pNext = STDLIB_GVP;
    sem_ci.flags = 0;
    sem_ci._pad  = 0;
    vkCreateSemaphore(vkctx.device, @sem_ci, STDLIB_GVP, @image_avail_sem);
    vkCreateSemaphore(vkctx.device, @sem_ci, STDLIB_GVP, @render_done_sem);

    VkFenceCreateInfo fence_ci;
    fence_ci.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fence_ci.pNext = STDLIB_GVP;
    fence_ci.flags = (u32)VK_FENCE_CREATE_SIGNALED_BIT;
    fence_ci._pad  = 0;
    vkCreateFence(vkctx.device, @fence_ci, STDLIB_GVP, @frame_fence);

    // ---- Transition cpu_image to GENERAL layout once ----
    VkCommandBufferBeginInfo begin_info;
    begin_info.sType            = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    begin_info.pNext            = STDLIB_GVP;
    begin_info.flags            = (u32)VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    begin_info.pInheritanceInfo = STDLIB_GVP;
    vkBeginCommandBuffer(cmd_buf, @begin_info);

    windows::vk_transition_image_layout(cmd_buf, cpu_image,
        VK_IMAGE_LAYOUT_PREINITIALIZED, VK_IMAGE_LAYOUT_GENERAL,
        (u32)VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, (u32)VK_PIPELINE_STAGE_TRANSFER_BIT,
        0, (u32)VK_ACCESS_TRANSFER_READ_BIT);

    vkEndCommandBuffer(cmd_buf);

    VkFence init_fence;
    vkCreateFence(vkctx.device, @fence_ci, STDLIB_GVP, @init_fence);
    vkResetFences(vkctx.device, 1, @init_fence);

    VkSubmitInfo init_submit;
    init_submit.sType                = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    init_submit.pNext                = STDLIB_GVP;
    init_submit.waitSemaphoreCount   = 0;
    init_submit._pad                 = 0;
    init_submit.pWaitSemaphores      = STDLIB_GVP;
    init_submit.pWaitDstStageMask    = STDLIB_GVP;
    init_submit.commandBufferCount   = 1;
    init_submit._pad2                = 0;
    init_submit.pCommandBuffers      = @cmd_buf;
    init_submit.signalSemaphoreCount = 0;
    init_submit._pad3                = 0;
    init_submit.pSignalSemaphores    = STDLIB_GVP;
    vkQueueSubmit(vkctx.graphics_queue, 1, @init_submit, init_fence);
    vkWaitForFences(vkctx.device, 1, @init_fence, 1, 0xFFFFFFFFFFFFFFFF);
    vkDestroyFence(vkctx.device, init_fence, STDLIB_GVP);

    // Load vkMapMemory / vkUnmapMemory (not wrapped in vulkan.fx)
    void* _vk_map_mem   = GetProcAddress(vk_dll, "vkMapMemory\0");
    void* _vk_unmap_mem = GetProcAddress(vk_dll, "vkUnmapMemory\0");

    // ---- View parameters (same as OpenGL version) ----
    double cx, cy, zoom, half_zoom, x_min, y_min,
           x_range, y_range, fx, fy,
           r, gv, b;

    cx   = -0.5;
    cy   =  0.0;
    zoom =  3.0;

    float zoom_speed, pan_speed, dt;
    zoom_speed = 1.5;
    pan_speed  = 0.6;

    int tile, dyn_max_iter,
        cols, rows, row, col, iter,
        cur_w, cur_h;
    bool moving;

    DWORD t_now, t_last;
    t_last = GetTickCount();

    RECT client_rect;
    WORD w_state, s_state, a_state, d_state, up_state, dn_state;

    while (win.process_messages())
    {
        // Delta time
        t_now  = GetTickCount();
        dt     = (float)(t_now - t_last) / 1000.0;
        t_last = t_now;
        if (dt > 0.1) { dt = 0.1; };

        // Query actual client area
        GetClientRect(win.handle, @client_rect);
        cur_w = client_rect.right  - client_rect.left;
        cur_h = client_rect.bottom - client_rect.top;
        if (cur_w < 1) { cur_w = 1; };
        if (cur_h < 1) { cur_h = 1; };

        w_state  = GetAsyncKeyState(VK_W);
        s_state  = GetAsyncKeyState(VK_S);
        a_state  = GetAsyncKeyState(VK_A);
        d_state  = GetAsyncKeyState(VK_D);
        up_state = GetAsyncKeyState(VK_UP);
        dn_state = GetAsyncKeyState(VK_DOWN);

        // Detect if any movement key is held for adaptive quality
        moving = ((w_state  `& 0x8000) != 0) |
                 ((s_state  `& 0x8000) != 0) |
                 ((a_state  `& 0x8000) != 0) |
                 ((d_state  `& 0x8000) != 0) |
                 ((up_state `& 0x8000) != 0) |
                 ((dn_state `& 0x8000) != 0);

        // Coarser tile + fewer iters while navigating, full quality when still
        tile = moving ? TILE_MOVING : TILE_STILL;

        cols = cur_w / tile;
        rows = cur_h / tile;
        if (cols < 1) { cols = 1; };
        if (rows < 1) { rows = 1; };

        // Scale max iterations with zoom depth
        if (zoom > 1.0)
        {
            dyn_max_iter = 128;
        }
        elif (zoom > 0.01)
        {
            dyn_max_iter = 256;
        }
        elif (zoom > 0.0001)
        {
            dyn_max_iter = 512;
        }
        else
        {
            dyn_max_iter = MAX_ITER;
        };
        // While moving, halve the iteration budget on top of tile coarsening
        if (moving) { dyn_max_iter = dyn_max_iter >> 1; };

        if ((w_state `& 0x8000) != 0)
        {
            zoom = zoom * (1.0 - (double)zoom_speed * (double)dt);
            if (zoom < 0.0000000001) { zoom = 0.0000000001; };
        };

        if ((s_state `& 0x8000) != 0)
        {
            zoom = zoom * (1.0 + (double)zoom_speed * (double)dt);
            if (zoom > 8.0) { zoom = 8.0; };
        };

        if ((a_state `& 0x8000) != 0)
        {
            cx = cx - zoom * (double)pan_speed * (double)dt;
        };

        if ((d_state `& 0x8000) != 0)
        {
            cx = cx + zoom * (double)pan_speed * (double)dt;
        };

        if ((up_state `& 0x8000) != 0)
        {
            cy = cy - zoom * (double)pan_speed * (double)dt;
        };

        if ((dn_state `& 0x8000) != 0)
        {
            cy = cy + zoom * (double)pan_speed * (double)dt;
        };

        // ---- Map the cpu_image memory and write pixels ----
        void* pixel_ptr;
        def{}* fp_map(VkDevice, VkDeviceMemory, u64, u64, u32, void**) -> VkResult = _vk_map_mem;
        *fp_map(vkctx.device, cpu_memory, 0, mem_req.size, 0, @pixel_ptr);

        half_zoom = zoom * 0.5;
        x_min   = cx - half_zoom;
        y_min   = cy - zoom * (double)img_h / (double)img_w * 0.5;
        x_range = zoom;
        y_range = zoom * (double)img_h / (double)img_w;

        // Write pixel data into the mapped image memory
        // Format is B8G8R8A8 or R8G8B8A8 (4 bytes per pixel)
        // Row pitch for a linear image equals img_w * 4 bytes
        u32* pixels;
        pixels = (u32*)pixel_ptr;

        row = 0;
        while (row < cur_h)
        {
            col = 0;
            while (col < cur_w)
            {
                // Map pixel to fractal coordinate
                fx = x_min + x_range * ((double)col + 0.5) / (double)cur_w;
                fy = y_min + y_range * ((double)row + 0.5) / (double)cur_h;

                // For moving mode, fill tile_size x tile_size blocks
                iter = mandelbrot(fx, fy, dyn_max_iter);
                iter_to_color(iter, dyn_max_iter, @r, @gv, @b);

                u32 ri, gi, bi, packed;
                ri = (u32)(r  * 255.0);
                gi = (u32)(gv * 255.0);
                bi = (u32)(b  * 255.0);

                // Pack as B8G8R8A8 (swapchain_format is B8G8R8A8_UNORM)
                packed = (bi) | (gi << 8) | (ri << 16) | (255 << 24);

                // Fill the tile block for this pixel
                int tr, tc;
                tr = 0;
                while (tr < tile)
                {
                    tc = 0;
                    while (tc < tile)
                    {
                        int pr, pc;
                        pr = row * tile + tr;
                        pc = col * tile + tc;
                        if (pr < (int)img_h & pc < (int)img_w)
                        {
                            pixels[pr * (int)img_w + pc] = packed;
                        };
                        tc++;
                    };
                    tr++;
                };

                col++;
            };
            row++;
        };

        def{}* fp_unmap(VkDevice, VkDeviceMemory) -> void = _vk_unmap_mem;
        *fp_unmap(vkctx.device, cpu_memory);

        // ---- Acquire swapchain image ----
        u32 sc_index;
        VkResult acq_res;
        acq_res = vkAcquireNextImageKHR(vkctx.device, vkctx.swapchain,
                      0xFFFFFFFFFFFFFFFF, image_avail_sem, (VkFence)0, @sc_index);

        if (acq_res == VK_ERROR_OUT_OF_DATE_KHR) { continue; };

        // ---- Wait for previous frame fence ----
        vkWaitForFences(vkctx.device, 1, @frame_fence, 1, 0xFFFFFFFFFFFFFFFF);
        vkResetFences(vkctx.device, 1, @frame_fence);

        // ---- Record command buffer: transition, copy, transition ----
        vkResetCommandBuffer(cmd_buf, 0);

        begin_info.flags = (u32)VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        vkBeginCommandBuffer(cmd_buf, @begin_info);

        // Transition swapchain image: UNDEFINED -> TRANSFER_DST_OPTIMAL
        windows::vk_transition_image_layout(cmd_buf, vkctx.swapchain_images[sc_index],
            VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            (u32)VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,  (u32)VK_PIPELINE_STAGE_TRANSFER_BIT,
            0, (u32)VK_ACCESS_TRANSFER_WRITE_BIT);

        // Copy cpu_image -> swapchain image
        VkImageCopyRegion copy_region;
        copy_region.src_aspectMask    = (u32)VK_IMAGE_ASPECT_COLOR_BIT;
        copy_region.src_mipLevel      = 0;
        copy_region.src_baseArrayLayer = 0;
        copy_region.src_layerCount    = 1;
        copy_region.src_x             = 0;
        copy_region.src_y             = 0;
        copy_region.src_z             = 0;
        copy_region.dst_aspectMask    = (u32)VK_IMAGE_ASPECT_COLOR_BIT;
        copy_region.dst_mipLevel      = 0;
        copy_region.dst_baseArrayLayer = 0;
        copy_region.dst_layerCount    = 1;
        copy_region.dst_x             = 0;
        copy_region.dst_y             = 0;
        copy_region.dst_z             = 0;
        copy_region.ext_w             = img_w;
        copy_region.ext_h             = img_h;
        copy_region.ext_d             = 1;

        vkCmdCopyImage(cmd_buf,
            cpu_image,                      VK_IMAGE_LAYOUT_GENERAL,
            vkctx.swapchain_images[sc_index], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1, @copy_region);

        // Transition swapchain image: TRANSFER_DST_OPTIMAL -> PRESENT_SRC_KHR
        windows::vk_transition_image_layout(cmd_buf, vkctx.swapchain_images[sc_index],
            VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
            (u32)VK_PIPELINE_STAGE_TRANSFER_BIT, (u32)VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
            (u32)VK_ACCESS_TRANSFER_WRITE_BIT, (u32)VK_ACCESS_MEMORY_READ_BIT);

        vkEndCommandBuffer(cmd_buf);

        // ---- Submit ----
        u32 wait_stage;
        wait_stage = (u32)VK_PIPELINE_STAGE_TRANSFER_BIT;

        VkSubmitInfo submit;
        submit.sType                = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submit.pNext                = STDLIB_GVP;
        submit.waitSemaphoreCount   = 1;
        submit._pad                 = 0;
        submit.pWaitSemaphores      = @image_avail_sem;
        submit.pWaitDstStageMask    = @wait_stage;
        submit.commandBufferCount   = 1;
        submit._pad2                = 0;
        submit.pCommandBuffers      = @cmd_buf;
        submit.signalSemaphoreCount = 1;
        submit._pad3                = 0;
        submit.pSignalSemaphores    = @render_done_sem;
        vkQueueSubmit(vkctx.graphics_queue, 1, @submit, frame_fence);

        // ---- Present ----
        VkPresentInfoKHR present_info;
        present_info.sType              = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
        present_info.pNext              = STDLIB_GVP;
        present_info.waitSemaphoreCount = 1;
        present_info.pWaitSemaphores    = @render_done_sem;
        present_info.swapchainCount     = 1;
        present_info.pSwapchains        = @vkctx.swapchain;
        present_info.pImageIndices      = @sc_index;
        present_info.pResults           = STDLIB_GVP;
        vkQueuePresentKHR(vkctx.present_queue, @present_info);
    };

    // ---- Cleanup ----
    vkDeviceWaitIdle(vkctx.device);

    vkDestroySemaphore(vkctx.device, image_avail_sem, STDLIB_GVP);
    vkDestroySemaphore(vkctx.device, render_done_sem, STDLIB_GVP);
    vkDestroyFence(vkctx.device, frame_fence, STDLIB_GVP);
    vkDestroyCommandPool(vkctx.device, cmd_pool, STDLIB_GVP);
    vkDestroyImage(vkctx.device, cpu_image, STDLIB_GVP);
    vkFreeMemory(vkctx.device, cpu_memory, STDLIB_GVP);

    vkctx.__exit();
    win.__exit();

    return 0;
};
