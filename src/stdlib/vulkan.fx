// Author: Karac V. Thweatt

// Flux Vulkan Library
// Provides Vulkan instance/device setup, swapchain, and compute pipeline helpers
// Windows-only: loads vulkan-1.dll at runtime via LoadLibraryA / GetProcAddress
#ifndef __WIN32_INTERFACE__
#import "redwindows.fx";
#endif

#ifndef __REDVULKAN__
#def __REDVULKAN__ 1;

// ============================================================================
// VULKAN BASE TYPES
// ============================================================================

unsigned data{64} as VkInstance;
unsigned data{64} as VkPhysicalDevice;
unsigned data{64} as VkDevice;
unsigned data{64} as VkQueue;
unsigned data{64} as VkSurfaceKHR;
unsigned data{64} as VkSwapchainKHR;
unsigned data{64} as VkImage;
unsigned data{64} as VkImageView;
unsigned data{64} as VkShaderModule;
unsigned data{64} as VkDescriptorSetLayout;
unsigned data{64} as VkPipelineLayout;
unsigned data{64} as VkPipeline;
unsigned data{64} as VkDescriptorPool;
unsigned data{64} as VkDescriptorSet;
unsigned data{64} as VkCommandPool;
unsigned data{64} as VkCommandBuffer;
unsigned data{64} as VkSemaphore;
unsigned data{64} as VkFence;
unsigned data{64} as VkDeviceMemory;
unsigned data{64} as VkBuffer;
unsigned data{64} as VkRenderPass;
unsigned data{64} as VkFramebuffer;
unsigned data{64} as VkSampler;

signed   data{32} as VkResult;
unsigned data{32} as VkFlags;
unsigned data{32} as VkBool32;
unsigned data{64} as VkDeviceSize;

// ============================================================================
// VULKAN RESULT CODES
// ============================================================================

global int VK_SUCCESS                        = 0,
           VK_NOT_READY                      = 1,
           VK_TIMEOUT                        = 2,
           VK_EVENT_SET                      = 3,
           VK_EVENT_RESET                    = 4,
           VK_INCOMPLETE                     = 5,
           VK_ERROR_OUT_OF_HOST_MEMORY       = -1,
           VK_ERROR_OUT_OF_DEVICE_MEMORY     = -2,
           VK_ERROR_INITIALIZATION_FAILED    = -3,
           VK_ERROR_DEVICE_LOST              = -4,
           VK_ERROR_LAYER_NOT_PRESENT        = -6,
           VK_ERROR_EXTENSION_NOT_PRESENT    = -7,
           VK_ERROR_FEATURE_NOT_PRESENT      = -8,
           VK_ERROR_INCOMPATIBLE_DRIVER      = -9,
           VK_ERROR_SURFACE_LOST_KHR        = -1000000000,
           VK_SUBOPTIMAL_KHR                 = 1000001003,
           VK_ERROR_OUT_OF_DATE_KHR         = -1000001004;

// ============================================================================
// VULKAN STRUCTURE TYPE ENUMS (sType)
// ============================================================================

global int VK_STRUCTURE_TYPE_APPLICATION_INFO                    = 0,
           VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO                = 1,
           VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO            = 2,
           VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO                  = 3,
           VK_STRUCTURE_TYPE_SUBMIT_INFO                         = 4,
           VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO                = 5,
           VK_STRUCTURE_TYPE_BIND_SPARSE_INFO                    = 7,
           VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO                  = 12,
           VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO                   = 14,
           VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO              = 15,
           VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO           = 16,
           VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO          = 17,
           VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO   = 18,
           VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO         = 30,
           VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO   = 32,
           VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO         = 33,
           VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO        = 34,
           VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET                = 35,
           VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO            = 39,
           VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO        = 40,
           VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO           = 42,
           VK_STRUCTURE_TYPE_FENCE_CREATE_INFO                   = 8,
           VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO               = 9,
           VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO        = 29,
           VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER                = 45,
           VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER               = 44,
           VK_STRUCTURE_TYPE_MEMORY_BARRIER                      = 46;

global int VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR      = 1000009000,
           VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR           = 1000001000,
           VK_STRUCTURE_TYPE_PRESENT_INFO_KHR                    = 1000001001;

// ============================================================================
// VULKAN FORMAT ENUMS
// ============================================================================

global int VK_FORMAT_UNDEFINED        = 0,
           VK_FORMAT_R8G8B8A8_UNORM   = 37,
           VK_FORMAT_R8G8B8A8_SRGB    = 43,
           VK_FORMAT_B8G8R8A8_UNORM   = 44,
           VK_FORMAT_B8G8R8A8_SRGB    = 50,
           VK_FORMAT_R32G32B32A32_SFLOAT = 109;

// ============================================================================
// VULKAN IMAGE / RESOURCE ENUMS
// ============================================================================

global int VK_IMAGE_LAYOUT_UNDEFINED                          = 0,
           VK_IMAGE_LAYOUT_GENERAL                            = 1,
           VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL           = 2,
           VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL               = 6,
           VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL               = 7,
           VK_IMAGE_LAYOUT_PREINITIALIZED                     = 8,
           VK_IMAGE_LAYOUT_PRESENT_SRC_KHR                   = 1000001002;

global int VK_IMAGE_USAGE_TRANSFER_SRC_BIT     = 0x00000001,
           VK_IMAGE_USAGE_TRANSFER_DST_BIT     = 0x00000002,
           VK_IMAGE_USAGE_SAMPLED_BIT          = 0x00000004,
           VK_IMAGE_USAGE_STORAGE_BIT          = 0x00000008,
           VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT = 0x00000010;

global int VK_IMAGE_ASPECT_COLOR_BIT = 0x00000001,
           VK_IMAGE_ASPECT_DEPTH_BIT = 0x00000002;

global int VK_IMAGE_TILING_OPTIMAL  = 0,
           VK_IMAGE_TILING_LINEAR   = 1;

global int VK_IMAGE_TYPE_2D = 1;

global int VK_SAMPLE_COUNT_1_BIT = 0x00000001;

global int VK_IMAGE_VIEW_TYPE_2D = 1;

// ============================================================================
// VULKAN PIPELINE STAGE / ACCESS FLAGS
// ============================================================================

global int VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT        = 0x00000001,
           VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT      = 0x00000800,
           VK_PIPELINE_STAGE_TRANSFER_BIT            = 0x00001000,
           VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT      = 0x00002000,
           VK_PIPELINE_STAGE_ALL_COMMANDS_BIT        = 0x00010000;

global int VK_ACCESS_SHADER_WRITE_BIT               = 0x00000040,
           VK_ACCESS_SHADER_READ_BIT                 = 0x00000020,
           VK_ACCESS_TRANSFER_READ_BIT               = 0x00000800,
           VK_ACCESS_TRANSFER_WRITE_BIT              = 0x00001000,
           VK_ACCESS_MEMORY_READ_BIT                 = 0x00008000;

// ============================================================================
// VULKAN QUEUE FLAGS
// ============================================================================

global int VK_QUEUE_GRAPHICS_BIT = 0x00000001,
           VK_QUEUE_COMPUTE_BIT  = 0x00000002,
           VK_QUEUE_TRANSFER_BIT = 0x00000004;

// ============================================================================
// VULKAN SHARING MODE / COMMAND BUFFER LEVEL
// ============================================================================

global int VK_SHARING_MODE_EXCLUSIVE  = 0,
           VK_SHARING_MODE_CONCURRENT = 1;

global int VK_COMMAND_BUFFER_LEVEL_PRIMARY   = 0,
           VK_COMMAND_BUFFER_LEVEL_SECONDARY = 1;

global int VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT      = 0x00000001,
           VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT     = 0x00000004;

// ============================================================================
// VULKAN MEMORY FLAGS
// ============================================================================

global int VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT      = 0x00000001,
           VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT       = 0x00000002,
           VK_MEMORY_PROPERTY_HOST_COHERENT_BIT      = 0x00000004;

// ============================================================================
// VULKAN DESCRIPTOR / SHADER STAGE FLAGS
// ============================================================================

global int VK_DESCRIPTOR_TYPE_SAMPLER                    = 0,
           VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE              = 2,
           VK_DESCRIPTOR_TYPE_STORAGE_IMAGE              = 3,
           VK_DESCRIPTOR_TYPE_STORAGE_BUFFER             = 7;

global int VK_SHADER_STAGE_VERTEX_BIT   = 0x00000001,
           VK_SHADER_STAGE_FRAGMENT_BIT = 0x00000010,
           VK_SHADER_STAGE_COMPUTE_BIT  = 0x00000020;

// ============================================================================
// SWAPCHAIN / SURFACE ENUMS
// ============================================================================

global int VK_PRESENT_MODE_IMMEDIATE_KHR    = 0,
           VK_PRESENT_MODE_MAILBOX_KHR      = 1,
           VK_PRESENT_MODE_FIFO_KHR         = 2,
           VK_PRESENT_MODE_FIFO_RELAXED_KHR = 3;

global int VK_COLOR_SPACE_SRGB_NONLINEAR_KHR = 0;

global int VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR = 0x00000001;

global int VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR = 0x00000001;

global int VK_FENCE_CREATE_SIGNALED_BIT = 0x00000001;

// ============================================================================
// VULKAN FILTER CONSTANT
// ============================================================================

global int VK_FILTER_NEAREST = 0,
           VK_FILTER_LINEAR  = 1;

// ============================================================================
// DEPENDENCY FLAGS
// ============================================================================

global int VK_DEPENDENCY_BY_REGION_BIT = 0x00000001;

// ============================================================================
// SUBPASS EXTERNAL
// ============================================================================

global int VK_SUBPASS_EXTERNAL = 0xFFFFFFFF;

// ============================================================================
// VULKAN STRUCTURES
// ============================================================================

struct VkExtent2D
{
    u32 width,
        height;
};

struct VkOffset2D
{
    i32 x, y;
};

struct VkRect2D
{
    VkOffset2D offset;
    VkExtent2D extent;
};

struct VkViewport
{
    float x, y,
          width, height,
          minDepth, maxDepth;
};

struct VkApplicationInfo
{
    i32     sType;
    u64*   pNext;
    byte*   pApplicationName;
    u32     applicationVersion;
    byte*   pEngineName;
    u32     engineVersion;
    u32     apiVersion;
};

struct VkInstanceCreateInfo
{
    i32     sType;
    u64*   pNext;
    u32     flags;
    u64*   pApplicationInfo;
    u32     enabledLayerCount;
    u64*   ppEnabledLayerNames;
    u32     enabledExtensionCount;
    u64*   ppEnabledExtensionNames;
};

struct VkDeviceQueueCreateInfo
{
    i32     sType;
    u64*   pNext;
    u32     flags;
    u32     queueFamilyIndex;
    u32     queueCount;
    float*  pQueuePriorities;
};

struct VkDeviceCreateInfo
{
    i32     sType;
    u64*   pNext;
    u32     flags;
    u32     queueCreateInfoCount;
    u64*   pQueueCreateInfos;
    u32     enabledLayerCount;
    u64*   ppEnabledLayerNames;
    u32     enabledExtensionCount;
    u64*   ppEnabledExtensionNames;
    u64*   pEnabledFeatures;
};

struct VkWin32SurfaceCreateInfoKHR
{
    i32         sType;
    u64*       pNext;
    u32         flags;
    HINSTANCE   hinstance;
    HWND        hwnd;
};

struct VkSurfaceCapabilitiesKHR
{
    u32         minImageCount;
    u32         maxImageCount;
    VkExtent2D  currentExtent;
    VkExtent2D  minImageExtent;
    VkExtent2D  maxImageExtent;
    u32         maxImageArrayLayers;
    u32         supportedTransforms;
    u32         currentTransform;
    u32         supportedCompositeAlpha;
    u32         supportedUsageFlags;
};

struct VkSurfaceFormatKHR
{
    i32 format;
    i32 colorSpace;
};

struct VkSwapchainCreateInfoKHR
{
    i32         sType;
    u64*       pNext;
    u32         flags;
    VkSurfaceKHR surface;
    u32         minImageCount;
    i32         imageFormat;
    i32         imageColorSpace;
    VkExtent2D  imageExtent;
    u32         imageArrayLayers;
    u32         imageUsage;
    i32         imageSharingMode;
    u32         queueFamilyIndexCount;
    u32*        pQueueFamilyIndices;
    u32         preTransform;
    u32         compositeAlpha;
    i32         presentMode;
    VkBool32    clipped;
    VkSwapchainKHR oldSwapchain;
};

struct VkPresentInfoKHR
{
    i32              sType;
    u64*            pNext;
    u32              waitSemaphoreCount;
    VkSemaphore*     pWaitSemaphores;
    u32              swapchainCount;
    VkSwapchainKHR*  pSwapchains;
    u32*             pImageIndices;
    VkResult*        pResults;
};

struct VkImageViewCreateInfo
{
    i32           sType;
    u64*         pNext;
    u32           flags;
    VkImage       image;
    i32           viewType;
    i32           format;
    // VkComponentMapping - 4 x i32
    i32           components_r;
    i32           components_g;
    i32           components_b;
    i32           components_a;
    // VkImageSubresourceRange
    u32           aspectMask;
    u32           baseMipLevel;
    u32           levelCount;
    u32           baseArrayLayer;
    u32           layerCount;
};

struct VkImageCreateInfo
{
    i32         sType;
    u64*       pNext;
    u32         flags;
    i32         imageType;
    i32         format;
    u32         extent_w;
    u32         extent_h;
    u32         extent_d;
    u32         mipLevels;
    u32         arrayLayers;
    u32         samples;
    i32         tiling;
    u32         usage;
    i32         sharingMode;
    u32         queueFamilyIndexCount;
    u32*        pQueueFamilyIndices;
    i32         initialLayout;
};

struct VkMemoryRequirements
{
    u64 size;
    u64 alignment;
    u32 memoryTypeBits;
    u32 _pad;
};

struct VkMemoryAllocateInfo
{
    i32 sType;
    u64* pNext;
    u64 allocationSize;
    u32 memoryTypeIndex;
    u32 _pad;
};

struct VkPhysicalDeviceMemoryProperties
{
    u32 memoryTypeCount;
    // 32 VkMemoryType structs, each = {propertyFlags(u32), heapIndex(u32)} = 8 bytes
    u32[64] memoryTypeData;
    u32 memoryHeapCount;
    u32 _pad;
    // 16 VkMemoryHeap structs each = {size(u64), flags(u32), _pad(u32)} = 16 bytes
    u64[32] memoryHeapData;
};

struct VkShaderModuleCreateInfo
{
    i32    sType;
    u64*  pNext;
    u32    flags;
    u32    _pad;
    u64    codeSize;
    u32*   pCode;
};

struct VkDescriptorSetLayoutBinding
{
    u32 binding;
    i32 descriptorType;
    u32 descriptorCount;
    u32 stageFlags;
    u64* pImmutableSamplers;
};

struct VkDescriptorSetLayoutCreateInfo
{
    i32    sType;
    u64*  pNext;
    u32    flags;
    u32    bindingCount;
    u64*  pBindings;
};

struct VkPushConstantRange
{
    u32 stageFlags;
    u32 offset;
    u32 size;
    u32 _pad;
};

struct VkPipelineLayoutCreateInfo
{
    i32    sType;
    u64*  pNext;
    u32    flags;
    u32    setLayoutCount;
    u64*  pSetLayouts;
    u32    pushConstantRangeCount;
    u32    _pad;
    u64*  pPushConstantRanges;
};

struct VkPipelineShaderStageCreateInfo
{
    i32    sType;
    u64*  pNext;
    u32    flags;
    u32    stage;
    VkShaderModule module;
    byte*  pName;
    u64*  pSpecializationInfo;
};

struct VkComputePipelineCreateInfo
{
    i32                          sType;
    u64*                        pNext;
    u32                          flags;
    u32                          _pad;
    VkPipelineShaderStageCreateInfo stage;
    VkPipelineLayout             layout;
    VkPipeline                   basePipelineHandle;
    i32                          basePipelineIndex;
    i32                          _pad2;
};

struct VkDescriptorPoolSize
{
    i32 type;
    u32 descriptorCount;
};

struct VkDescriptorPoolCreateInfo
{
    i32    sType;
    u64*  pNext;
    u32    flags;
    u32    maxSets;
    u32    poolSizeCount;
    u32    _pad;
    u64*  pPoolSizes;
};

struct VkDescriptorSetAllocateInfo
{
    i32    sType;
    u64*  pNext;
    VkDescriptorPool descriptorPool;
    u32    descriptorSetCount;
    u32    _pad;
    u64*  pSetLayouts;
};

struct VkDescriptorImageInfo
{
    VkSampler     sampler;
    VkImageView   imageView;
    i32           imageLayout;
    i32           _pad;
};

struct VkWriteDescriptorSet
{
    i32             sType;
    u64*           pNext;
    VkDescriptorSet dstSet;
    u32             dstBinding;
    u32             dstArrayElement;
    u32             descriptorCount;
    i32             descriptorType;
    u64*           pImageInfo;
    u64*           pBufferInfo;
    u64*           pTexelBufferView;
};

struct VkCommandPoolCreateInfo
{
    i32  sType;
    u64* pNext;
    u32  flags;
    u32  queueFamilyIndex;
};

struct VkCommandBufferAllocateInfo
{
    i32             sType;
    u64*           pNext;
    VkCommandPool   commandPool;
    i32             level;
    u32             commandBufferCount;
};

struct VkCommandBufferBeginInfo
{
    i32    sType;
    u64*  pNext;
    u32    flags;
    u64*  pInheritanceInfo;
};

struct VkImageMemoryBarrier
{
    i32           sType;
    u64*         pNext;
    u32           srcAccessMask;
    u32           dstAccessMask;
    i32           oldLayout;
    i32           newLayout;
    u32           srcQueueFamilyIndex;
    u32           dstQueueFamilyIndex;
    VkImage       image;
    // VkImageSubresourceRange
    u32           aspectMask;
    u32           baseMipLevel;
    u32           levelCount;
    u32           baseArrayLayer;
    u32           layerCount;
};

struct VkSubmitInfo
{
    i32              sType;
    u64*            pNext;
    u32              waitSemaphoreCount;
    u32              _pad;
    VkSemaphore*     pWaitSemaphores;
    u32*             pWaitDstStageMask;
    u32              commandBufferCount;
    u32              _pad2;
    VkCommandBuffer* pCommandBuffers;
    u32              signalSemaphoreCount;
    u32              _pad3;
    VkSemaphore*     pSignalSemaphores;
};

struct VkFenceCreateInfo
{
    i32    sType;
    u64*  pNext;
    u32    flags;
    u32    _pad;
};

struct VkSemaphoreCreateInfo
{
    i32   sType;
    u64* pNext;
    u32   flags;
    u32   _pad;
};

struct VkQueueFamilyProperties
{
    u32 queueFlags;
    u32 queueCount;
    u32 timestampValidBits;
    u32 minImageTransferGranularity_w;
    u32 minImageTransferGranularity_h;
    u32 minImageTransferGranularity_d;
};

struct VkPhysicalDeviceProperties
{
    u32     apiVersion;
    u32     driverVersion;
    u32     vendorID;
    u32     deviceID;
    i32     deviceType;
    byte[256] deviceName;
    byte[16]  pipelineCacheUUID;
    // VkPhysicalDeviceLimits - large struct, we only need it to exist for sizing
    // 504 bytes of limits (we pad to match)
    u32[504] limitsData;
    // VkPhysicalDeviceSparseProperties - 5 bools
    u32[5] sparseData;
};

// ============================================================================
// VULKAN FUNCTION POINTER GLOBALS
// Loaded at runtime via vk_load()
// ============================================================================

global void* _vkCreateInstance              = STDLIB_GVP,
             _vkDestroyInstance             = STDLIB_GVP,
             _vkEnumeratePhysicalDevices    = STDLIB_GVP,
             _vkGetPhysicalDeviceProperties = STDLIB_GVP,
             _vkGetPhysicalDeviceQueueFamilyProperties = STDLIB_GVP,
             _vkGetPhysicalDeviceMemoryProperties = STDLIB_GVP,
             _vkCreateDevice                = STDLIB_GVP,
             _vkDestroyDevice               = STDLIB_GVP,
             _vkGetDeviceQueue              = STDLIB_GVP,
             _vkQueueSubmit                 = STDLIB_GVP,
             _vkQueueWaitIdle               = STDLIB_GVP,
             _vkDeviceWaitIdle              = STDLIB_GVP,

             _vkCreateWin32SurfaceKHR       = STDLIB_GVP,
             _vkDestroySurfaceKHR           = STDLIB_GVP,
             _vkGetPhysicalDeviceSurfaceSupportKHR      = STDLIB_GVP,
             _vkGetPhysicalDeviceSurfaceCapabilitiesKHR = STDLIB_GVP,
             _vkGetPhysicalDeviceSurfaceFormatsKHR      = STDLIB_GVP,
             _vkGetPhysicalDeviceSurfacePresentModesKHR = STDLIB_GVP,
             _vkCreateSwapchainKHR          = STDLIB_GVP,
             _vkDestroySwapchainKHR         = STDLIB_GVP,
             _vkGetSwapchainImagesKHR       = STDLIB_GVP,
             _vkAcquireNextImageKHR         = STDLIB_GVP,
             _vkQueuePresentKHR             = STDLIB_GVP,

             _vkCreateImageView             = STDLIB_GVP,
             _vkDestroyImageView            = STDLIB_GVP,
             _vkCreateImage                 = STDLIB_GVP,
             _vkDestroyImage                = STDLIB_GVP,
             _vkGetImageMemoryRequirements  = STDLIB_GVP,
             _vkAllocateMemory              = STDLIB_GVP,
             _vkFreeMemory                  = STDLIB_GVP,
             _vkBindImageMemory             = STDLIB_GVP,

             _vkCreateShaderModule          = STDLIB_GVP,
             _vkDestroyShaderModule         = STDLIB_GVP,
             _vkCreateDescriptorSetLayout   = STDLIB_GVP,
             _vkDestroyDescriptorSetLayout  = STDLIB_GVP,
             _vkCreatePipelineLayout        = STDLIB_GVP,
             _vkDestroyPipelineLayout       = STDLIB_GVP,
             _vkCreateComputePipelines      = STDLIB_GVP,
             _vkDestroyPipeline             = STDLIB_GVP,
             _vkCreateDescriptorPool        = STDLIB_GVP,
             _vkDestroyDescriptorPool       = STDLIB_GVP,
             _vkAllocateDescriptorSets      = STDLIB_GVP,
             _vkUpdateDescriptorSets        = STDLIB_GVP,

             _vkCreateCommandPool           = STDLIB_GVP,
             _vkDestroyCommandPool          = STDLIB_GVP,
             _vkAllocateCommandBuffers      = STDLIB_GVP,
             _vkFreeCommandBuffers          = STDLIB_GVP,
             _vkBeginCommandBuffer          = STDLIB_GVP,
             _vkEndCommandBuffer            = STDLIB_GVP,
             _vkResetCommandBuffer          = STDLIB_GVP,
             _vkCmdPipelineBarrier          = STDLIB_GVP,
             _vkCmdBindPipeline             = STDLIB_GVP,
             _vkCmdBindDescriptorSets       = STDLIB_GVP,
             _vkCmdPushConstants            = STDLIB_GVP,
             _vkCmdDispatch                 = STDLIB_GVP,
             _vkCmdCopyImage                = STDLIB_GVP,

             _vkCreateFence                 = STDLIB_GVP,
             _vkDestroyFence                = STDLIB_GVP,
             _vkResetFences                 = STDLIB_GVP,
             _vkWaitForFences               = STDLIB_GVP,
             _vkCreateSemaphore             = STDLIB_GVP,
             _vkDestroySemaphore            = STDLIB_GVP;

// ============================================================================
// VULKAN FUNCTION CALL WRAPPERS
// Each wrapper casts the global void* to a function pointer and dispatches.
// ============================================================================

def vkCreateInstance(void* pCreateInfo, void* pAllocator, VkInstance* pInstance) -> VkResult
{
    def{}* fp(void*, void*, void*) -> VkResult = @_vkCreateInstance;
    return fp(pCreateInfo, pAllocator, pInstance);
};

def vkDestroyInstance(VkInstance instance, void* pAllocator) -> void
{
    def{}* fp(VkInstance, void*) -> void = @_vkDestroyInstance;
    fp(instance, pAllocator);
    return;
};

def vkEnumeratePhysicalDevices(VkInstance instance, u32* pPhysicalDeviceCount, VkPhysicalDevice* pPhysicalDevices) -> VkResult
{
    def{}* fp(VkInstance, void*, void*) -> VkResult = @_vkEnumeratePhysicalDevices;
    return fp(instance, pPhysicalDeviceCount, pPhysicalDevices);
};

def vkGetPhysicalDeviceProperties(VkPhysicalDevice physicalDevice, void* pProperties) -> void
{
    def{}* fp(VkPhysicalDevice, void*) -> void = @_vkGetPhysicalDeviceProperties;
    fp(physicalDevice, pProperties);
    return;
};

def vkGetPhysicalDeviceQueueFamilyProperties(VkPhysicalDevice physicalDevice, u32* pCount, void* pQueueFamilyProperties) -> void
{
    def{}* fp(VkPhysicalDevice, void*, void*) -> void = @_vkGetPhysicalDeviceQueueFamilyProperties;
    fp(physicalDevice, pCount, pQueueFamilyProperties);
    return;
};

def vkGetPhysicalDeviceMemoryProperties(VkPhysicalDevice physicalDevice, void* pMemoryProperties) -> void
{
    def{}* fp(VkPhysicalDevice, void*) -> void = @_vkGetPhysicalDeviceMemoryProperties;
    fp(physicalDevice, pMemoryProperties);
    return;
};

def vkCreateDevice(VkPhysicalDevice physicalDevice, void* pCreateInfo, void* pAllocator, VkDevice* pDevice) -> VkResult
{
    def{}* fp(VkPhysicalDevice, void*, void*, void*) -> VkResult = _vkCreateDevice;
    return fp(physicalDevice, pCreateInfo, pAllocator, pDevice);
};

def vkDestroyDevice(VkDevice device, void* pAllocator) -> void
{
    def{}* fp(VkDevice, void*) -> void = @_vkDestroyDevice;
    fp(device, pAllocator);
    return;
};

def vkGetDeviceQueue(VkDevice device, u32 queueFamilyIndex, u32 queueIndex, VkQueue* pQueue) -> void
{
    def{}* fp(VkDevice, u32, u32, void*) -> void = @_vkGetDeviceQueue;
    fp(device, queueFamilyIndex, queueIndex, pQueue);
    return;
};

def vkQueueSubmit(VkQueue queue, u32 submitCount, void* pSubmits, VkFence fence) -> VkResult
{
    def{}* fp(VkQueue, u32, void*, VkFence) -> VkResult = _vkQueueSubmit;
    return fp(queue, submitCount, pSubmits, fence);
};

def vkQueueWaitIdle(VkQueue queue) -> VkResult
{
    def{}* fp(VkQueue) -> VkResult = _vkQueueWaitIdle;
    return fp(queue);
};

def vkDeviceWaitIdle(VkDevice device) -> VkResult
{
    def{}* fp(VkDevice) -> VkResult = _vkDeviceWaitIdle;
    return fp(device);
};

def vkCreateWin32SurfaceKHR(VkInstance instance, void* pCreateInfo, void* pAllocator, VkSurfaceKHR* pSurface) -> VkResult
{
    def{}* fp(VkInstance, void*, void*, void*) -> VkResult = _vkCreateWin32SurfaceKHR;
    return fp(instance, pCreateInfo, pAllocator, pSurface);
};

def vkDestroySurfaceKHR(VkInstance instance, VkSurfaceKHR surface, void* pAllocator) -> void
{
    def{}* fp(VkInstance, VkSurfaceKHR, void*) -> void = @_vkDestroySurfaceKHR;
    fp(instance, surface, pAllocator);
    return;
};

def vkGetPhysicalDeviceSurfaceSupportKHR(VkPhysicalDevice physicalDevice, u32 queueFamilyIndex, VkSurfaceKHR surface, VkBool32* pSupported) -> VkResult
{
    def{}* fp(VkPhysicalDevice, u32, VkSurfaceKHR, void*) -> VkResult = _vkGetPhysicalDeviceSurfaceSupportKHR;
    return fp(physicalDevice, queueFamilyIndex, surface, pSupported);
};

def vkGetPhysicalDeviceSurfaceCapabilitiesKHR(VkPhysicalDevice physicalDevice, VkSurfaceKHR surface, void* pSurfaceCapabilities) -> VkResult
{
    def{}* fp(VkPhysicalDevice, VkSurfaceKHR, void*) -> VkResult = _vkGetPhysicalDeviceSurfaceCapabilitiesKHR;
    return fp(physicalDevice, surface, pSurfaceCapabilities);
};

def vkGetPhysicalDeviceSurfaceFormatsKHR(VkPhysicalDevice physicalDevice, VkSurfaceKHR surface, u32* pSurfaceFormatCount, void* pSurfaceFormats) -> VkResult
{
    def{}* fp(VkPhysicalDevice, VkSurfaceKHR, void*, void*) -> VkResult = _vkGetPhysicalDeviceSurfaceFormatsKHR;
    return fp(physicalDevice, surface, pSurfaceFormatCount, pSurfaceFormats);
};

def vkGetPhysicalDeviceSurfacePresentModesKHR(VkPhysicalDevice physicalDevice, VkSurfaceKHR surface, u32* pPresentModeCount, void* pPresentModes) -> VkResult
{
    def{}* fp(VkPhysicalDevice, VkSurfaceKHR, void*, void*) -> VkResult = _vkGetPhysicalDeviceSurfacePresentModesKHR;
    return fp(physicalDevice, surface, pPresentModeCount, pPresentModes);
};

def vkCreateSwapchainKHR(VkDevice device, void* pCreateInfo, void* pAllocator, VkSwapchainKHR* pSwapchain) -> VkResult
{
    def{}* fp(VkDevice, void*, void*, void*) -> VkResult = _vkCreateSwapchainKHR;
    return fp(device, pCreateInfo, pAllocator, pSwapchain);
};

def vkDestroySwapchainKHR(VkDevice device, VkSwapchainKHR swapchain, void* pAllocator) -> void
{
    def{}* fp(VkDevice, VkSwapchainKHR, void*) -> void = @_vkDestroySwapchainKHR;
    fp(device, swapchain, pAllocator);
    return;
};

def vkGetSwapchainImagesKHR(VkDevice device, VkSwapchainKHR swapchain, u32* pSwapchainImageCount, VkImage* pSwapchainImages) -> VkResult
{
    def{}* fp(VkDevice, VkSwapchainKHR, void*, void*) -> VkResult = _vkGetSwapchainImagesKHR;
    return fp(device, swapchain, pSwapchainImageCount, pSwapchainImages);
};

def vkAcquireNextImageKHR(VkDevice device, VkSwapchainKHR swapchain, u64 timeout, VkSemaphore semaphore, VkFence fence, u32* pImageIndex) -> VkResult
{
    def{}* fp(VkDevice, VkSwapchainKHR, u64, VkSemaphore, VkFence, void*) -> VkResult = _vkAcquireNextImageKHR;
    return fp(device, swapchain, timeout, semaphore, fence, pImageIndex);
};

def vkQueuePresentKHR(VkQueue queue, void* pPresentInfo) -> VkResult
{
    def{}* fp(VkQueue, void*) -> VkResult = _vkQueuePresentKHR;
    return fp(queue, pPresentInfo);
};

def vkCreateImageView(VkDevice device, void* pCreateInfo, void* pAllocator, VkImageView* pView) -> VkResult
{
    def{}* fp(VkDevice, void*, void*, void*) -> VkResult = _vkCreateImageView;
    return fp(device, pCreateInfo, pAllocator, pView);
};

def vkDestroyImageView(VkDevice device, VkImageView imageView, void* pAllocator) -> void
{
    def{}* fp(VkDevice, VkImageView, void*) -> void = @_vkDestroyImageView;
    fp(device, imageView, pAllocator);
    return;
};

def vkCreateImage(VkDevice device, void* pCreateInfo, void* pAllocator, VkImage* pImage) -> VkResult
{
    def{}* fp(VkDevice, void*, void*, void*) -> VkResult = _vkCreateImage;
    return fp(device, pCreateInfo, pAllocator, pImage);
};

def vkDestroyImage(VkDevice device, VkImage image, void* pAllocator) -> void
{
    def{}* fp(VkDevice, VkImage, void*) -> void = @_vkDestroyImage;
    fp(device, image, pAllocator);
    return;
};

def vkGetImageMemoryRequirements(VkDevice device, VkImage image, void* pMemoryRequirements) -> void
{
    def{}* fp(VkDevice, VkImage, void*) -> void = @_vkGetImageMemoryRequirements;
    fp(device, image, pMemoryRequirements);
    return;
};

def vkAllocateMemory(VkDevice device, void* pAllocateInfo, void* pAllocator, VkDeviceMemory* pMemory) -> VkResult
{
    def{}* fp(VkDevice, void*, void*, void*) -> VkResult = _vkAllocateMemory;
    return fp(device, pAllocateInfo, pAllocator, pMemory);
};

def vkFreeMemory(VkDevice device, VkDeviceMemory memory, void* pAllocator) -> void
{
    def{}* fp(VkDevice, VkDeviceMemory, void*) -> void = @_vkFreeMemory;
    fp(device, memory, pAllocator);
    return;
};

def vkBindImageMemory(VkDevice device, VkImage image, VkDeviceMemory memory, u64 memoryOffset) -> VkResult
{
    def{}* fp(VkDevice, VkImage, VkDeviceMemory, u64) -> VkResult = _vkBindImageMemory;
    return fp(device, image, memory, memoryOffset);
};

def vkCreateShaderModule(VkDevice device, void* pCreateInfo, void* pAllocator, VkShaderModule* pShaderModule) -> VkResult
{
    def{}* fp(VkDevice, void*, void*, void*) -> VkResult = _vkCreateShaderModule;
    return fp(device, pCreateInfo, pAllocator, pShaderModule);
};

def vkDestroyShaderModule(VkDevice device, VkShaderModule shaderModule, void* pAllocator) -> void
{
    def{}* fp(VkDevice, VkShaderModule, void*) -> void = @_vkDestroyShaderModule;
    fp(device, shaderModule, pAllocator);
    return;
};

def vkCreateDescriptorSetLayout(VkDevice device, void* pCreateInfo, void* pAllocator, VkDescriptorSetLayout* pSetLayout) -> VkResult
{
    def{}* fp(VkDevice, void*, void*, void*) -> VkResult = _vkCreateDescriptorSetLayout;
    return fp(device, pCreateInfo, pAllocator, pSetLayout);
};

def vkDestroyDescriptorSetLayout(VkDevice device, VkDescriptorSetLayout descriptorSetLayout, void* pAllocator) -> void
{
    def{}* fp(VkDevice, VkDescriptorSetLayout, void*) -> void = @_vkDestroyDescriptorSetLayout;
    fp(device, descriptorSetLayout, pAllocator);
    return;
};

def vkCreatePipelineLayout(VkDevice device, void* pCreateInfo, void* pAllocator, VkPipelineLayout* pPipelineLayout) -> VkResult
{
    def{}* fp(VkDevice, void*, void*, void*) -> VkResult = _vkCreatePipelineLayout;
    return fp(device, pCreateInfo, pAllocator, pPipelineLayout);
};

def vkDestroyPipelineLayout(VkDevice device, VkPipelineLayout pipelineLayout, void* pAllocator) -> void
{
    def{}* fp(VkDevice, VkPipelineLayout, void*) -> void = @_vkDestroyPipelineLayout;
    fp(device, pipelineLayout, pAllocator);
    return;
};

def vkCreateComputePipelines(VkDevice device, u64 pipelineCache, u32 createInfoCount, void* pCreateInfos, void* pAllocator, VkPipeline* pPipelines) -> VkResult
{
    def{}* fp(VkDevice, u64, u32, void*, void*, void*) -> VkResult = _vkCreateComputePipelines;
    return fp(device, pipelineCache, createInfoCount, pCreateInfos, pAllocator, pPipelines);
};

def vkDestroyPipeline(VkDevice device, VkPipeline pipeline, void* pAllocator) -> void
{
    def{}* fp(VkDevice, VkPipeline, void*) -> void = @_vkDestroyPipeline;
    fp(device, pipeline, pAllocator);
    return;
};

def vkCreateDescriptorPool(VkDevice device, void* pCreateInfo, void* pAllocator, VkDescriptorPool* pDescriptorPool) -> VkResult
{
    def{}* fp(VkDevice, void*, void*, void*) -> VkResult = _vkCreateDescriptorPool;
    return fp(device, pCreateInfo, pAllocator, pDescriptorPool);
};

def vkDestroyDescriptorPool(VkDevice device, VkDescriptorPool descriptorPool, void* pAllocator) -> void
{
    def{}* fp(VkDevice, VkDescriptorPool, void*) -> void = @_vkDestroyDescriptorPool;
    fp(device, descriptorPool, pAllocator);
    return;
};

def vkAllocateDescriptorSets(VkDevice device, void* pAllocateInfo, VkDescriptorSet* pDescriptorSets) -> VkResult
{
    def{}* fp(VkDevice, void*, void*) -> VkResult = _vkAllocateDescriptorSets;
    return fp(device, pAllocateInfo, pDescriptorSets);
};

def vkUpdateDescriptorSets(VkDevice device, u32 descriptorWriteCount, void* pDescriptorWrites, u32 descriptorCopyCount, void* pDescriptorCopies) -> void
{
    def{}* fp(VkDevice, u32, void*, u32, void*) -> void = @_vkUpdateDescriptorSets;
    fp(device, descriptorWriteCount, pDescriptorWrites, descriptorCopyCount, pDescriptorCopies);
    return;
};

def vkCreateCommandPool(VkDevice device, void* pCreateInfo, void* pAllocator, VkCommandPool* pCommandPool) -> VkResult
{
    def{}* fp(VkDevice, void*, void*, void*) -> VkResult = _vkCreateCommandPool;
    return fp(device, pCreateInfo, pAllocator, pCommandPool);
};

def vkDestroyCommandPool(VkDevice device, VkCommandPool commandPool, void* pAllocator) -> void
{
    def{}* fp(VkDevice, VkCommandPool, void*) -> void = @_vkDestroyCommandPool;
    fp(device, commandPool, pAllocator);
    return;
};

def vkAllocateCommandBuffers(VkDevice device, void* pAllocateInfo, VkCommandBuffer* pCommandBuffers) -> VkResult
{
    def{}* fp(VkDevice, void*, void*) -> VkResult = _vkAllocateCommandBuffers;
    return fp(device, pAllocateInfo, pCommandBuffers);
};

def vkFreeCommandBuffers(VkDevice device, VkCommandPool commandPool, u32 commandBufferCount, VkCommandBuffer* pCommandBuffers) -> void
{
    def{}* fp(VkDevice, VkCommandPool, u32, void*) -> void = @_vkFreeCommandBuffers;
    fp(device, commandPool, commandBufferCount, pCommandBuffers);
    return;
};

def vkBeginCommandBuffer(VkCommandBuffer commandBuffer, void* pBeginInfo) -> VkResult
{
    def{}* fp(VkCommandBuffer, void*) -> VkResult = _vkBeginCommandBuffer;
    return fp(commandBuffer, pBeginInfo);
};

def vkEndCommandBuffer(VkCommandBuffer commandBuffer) -> VkResult
{
    def{}* fp(VkCommandBuffer) -> VkResult = _vkEndCommandBuffer;
    return fp(commandBuffer);
};

def vkResetCommandBuffer(VkCommandBuffer commandBuffer, u32 flags) -> VkResult
{
    def{}* fp(VkCommandBuffer, u32) -> VkResult = _vkResetCommandBuffer;
    return fp(commandBuffer, flags);
};

def vkCmdPipelineBarrier(VkCommandBuffer commandBuffer,
                         u32 srcStageMask, u32 dstStageMask, u32 dependencyFlags,
                         u32 memoryBarrierCount, void* pMemoryBarriers,
                         u32 bufferMemoryBarrierCount, void* pBufferMemoryBarriers,
                         u32 imageMemoryBarrierCount, void* pImageMemoryBarriers) -> void
{
    def{}* fp(VkCommandBuffer, u32, u32, u32, u32, void*, u32, void*, u32, void*) -> void = @_vkCmdPipelineBarrier;
    fp(commandBuffer, srcStageMask, dstStageMask, dependencyFlags,
        memoryBarrierCount, pMemoryBarriers,
        bufferMemoryBarrierCount, pBufferMemoryBarriers,
        imageMemoryBarrierCount, pImageMemoryBarriers);
    return;
};

def vkCmdBindPipeline(VkCommandBuffer commandBuffer, i32 pipelineBindPoint, VkPipeline pipeline) -> void
{
    def{}* fp(VkCommandBuffer, i32, VkPipeline) -> void = @_vkCmdBindPipeline;
    fp(commandBuffer, pipelineBindPoint, pipeline);
    return;
};

def vkCmdBindDescriptorSets(VkCommandBuffer commandBuffer, i32 pipelineBindPoint, VkPipelineLayout layout,
                             u32 firstSet, u32 descriptorSetCount, VkDescriptorSet* pDescriptorSets,
                             u32 dynamicOffsetCount, u32* pDynamicOffsets) -> void
{
    def{}* fp(VkCommandBuffer, i32, VkPipelineLayout, u32, u32, void*, u32, void*) -> void = @_vkCmdBindDescriptorSets;
    fp(commandBuffer, pipelineBindPoint, layout, firstSet, descriptorSetCount, pDescriptorSets, dynamicOffsetCount, pDynamicOffsets);
    return;
};

def vkCmdPushConstants(VkCommandBuffer commandBuffer, VkPipelineLayout layout, u32 stageFlags, u32 offset, u32 size, void* pValues) -> void
{
    def{}* fp(VkCommandBuffer, VkPipelineLayout, u32, u32, u32, void*) -> void = @_vkCmdPushConstants;
    fp(commandBuffer, layout, stageFlags, offset, size, pValues);
    return;
};

def vkCmdDispatch(VkCommandBuffer commandBuffer, u32 groupCountX, u32 groupCountY, u32 groupCountZ) -> void
{
    def{}* fp(VkCommandBuffer, u32, u32, u32) -> void = @_vkCmdDispatch;
    fp(commandBuffer, groupCountX, groupCountY, groupCountZ);
    return;
};

def vkCmdCopyImage(VkCommandBuffer commandBuffer,
                   VkImage srcImage, i32 srcImageLayout,
                   VkImage dstImage, i32 dstImageLayout,
                   u32 regionCount, void* pRegions) -> void
{
    def{}* fp(VkCommandBuffer, VkImage, i32, VkImage, i32, u32, void*) -> void = @_vkCmdCopyImage;
    fp(commandBuffer, srcImage, srcImageLayout, dstImage, dstImageLayout, regionCount, pRegions);
    return;
};

def vkCreateFence(VkDevice device, void* pCreateInfo, void* pAllocator, VkFence* pFence) -> VkResult
{
    def{}* fp(VkDevice, void*, void*, void*) -> VkResult = _vkCreateFence;
    return fp(device, pCreateInfo, pAllocator, pFence);
};

def vkDestroyFence(VkDevice device, VkFence fence, void* pAllocator) -> void
{
    def{}* fp(VkDevice, VkFence, void*) -> void = @_vkDestroyFence;
    fp(device, fence, pAllocator);
    return;
};

def vkResetFences(VkDevice device, u32 fenceCount, VkFence* pFences) -> VkResult
{
    def{}* fp(VkDevice, u32, void*) -> VkResult = _vkResetFences;
    return fp(device, fenceCount, pFences);
};

def vkWaitForFences(VkDevice device, u32 fenceCount, VkFence* pFences, VkBool32 waitAll, u64 timeout) -> VkResult
{
    def{}* fp(VkDevice, u32, void*, VkBool32, u64) -> VkResult = _vkWaitForFences;
    return fp(device, fenceCount, pFences, waitAll, timeout);
};

def vkCreateSemaphore(VkDevice device, void* pCreateInfo, void* pAllocator, VkSemaphore* pSemaphore) -> VkResult
{
    def{}* fp(VkDevice, void*, void*, void*) -> VkResult = _vkCreateSemaphore;
    return fp(device, pCreateInfo, pAllocator, pSemaphore);
};

def vkDestroySemaphore(VkDevice device, VkSemaphore semaphore, void* pAllocator) -> void
{
    def{}* fp(VkDevice, VkSemaphore, void*) -> void = @_vkDestroySemaphore;
    fp(device, semaphore, pAllocator);
    return;
};

// ============================================================================
// PIPELINE BIND POINT
// ============================================================================

global int VK_PIPELINE_BIND_POINT_COMPUTE = 1;

// ============================================================================
// VK_LOADER - Loads all Vulkan function pointers from vulkan-1.dll
// ============================================================================

namespace standard
{
    namespace system
    {
        namespace windows
        {
            // Load all Vulkan entry points from vulkan-1.dll
            // Returns the DLL handle, or null on failure
            def vk_load() -> void*
            {
                void* dll = LoadLibraryA("vulkan-1.dll\0");
                if (dll == STDLIB_GVP) { return STDLIB_GVP; };

                _vkCreateInstance              = GetProcAddress(dll, "vkCreateInstance\0");
                _vkDestroyInstance             = GetProcAddress(dll, "vkDestroyInstance\0");
                _vkEnumeratePhysicalDevices    = GetProcAddress(dll, "vkEnumeratePhysicalDevices\0");
                _vkGetPhysicalDeviceProperties = GetProcAddress(dll, "vkGetPhysicalDeviceProperties\0");
                _vkGetPhysicalDeviceQueueFamilyProperties = GetProcAddress(dll, "vkGetPhysicalDeviceQueueFamilyProperties\0");
                _vkGetPhysicalDeviceMemoryProperties = GetProcAddress(dll, "vkGetPhysicalDeviceMemoryProperties\0");
                _vkCreateDevice                = GetProcAddress(dll, "vkCreateDevice\0");
                _vkDestroyDevice               = GetProcAddress(dll, "vkDestroyDevice\0");
                _vkGetDeviceQueue              = GetProcAddress(dll, "vkGetDeviceQueue\0");
                _vkQueueSubmit                 = GetProcAddress(dll, "vkQueueSubmit\0");
                _vkQueueWaitIdle               = GetProcAddress(dll, "vkQueueWaitIdle\0");
                _vkDeviceWaitIdle              = GetProcAddress(dll, "vkDeviceWaitIdle\0");

                _vkCreateWin32SurfaceKHR       = GetProcAddress(dll, "vkCreateWin32SurfaceKHR\0");
                _vkDestroySurfaceKHR           = GetProcAddress(dll, "vkDestroySurfaceKHR\0");
                _vkGetPhysicalDeviceSurfaceSupportKHR      = GetProcAddress(dll, "vkGetPhysicalDeviceSurfaceSupportKHR\0");
                _vkGetPhysicalDeviceSurfaceCapabilitiesKHR = GetProcAddress(dll, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR\0");
                _vkGetPhysicalDeviceSurfaceFormatsKHR      = GetProcAddress(dll, "vkGetPhysicalDeviceSurfaceFormatsKHR\0");
                _vkGetPhysicalDeviceSurfacePresentModesKHR = GetProcAddress(dll, "vkGetPhysicalDeviceSurfacePresentModesKHR\0");
                _vkCreateSwapchainKHR          = GetProcAddress(dll, "vkCreateSwapchainKHR\0");
                _vkDestroySwapchainKHR         = GetProcAddress(dll, "vkDestroySwapchainKHR\0");
                _vkGetSwapchainImagesKHR       = GetProcAddress(dll, "vkGetSwapchainImagesKHR\0");
                _vkAcquireNextImageKHR         = GetProcAddress(dll, "vkAcquireNextImageKHR\0");
                _vkQueuePresentKHR             = GetProcAddress(dll, "vkQueuePresentKHR\0");

                _vkCreateImageView             = GetProcAddress(dll, "vkCreateImageView\0");
                _vkDestroyImageView            = GetProcAddress(dll, "vkDestroyImageView\0");
                _vkCreateImage                 = GetProcAddress(dll, "vkCreateImage\0");
                _vkDestroyImage                = GetProcAddress(dll, "vkDestroyImage\0");
                _vkGetImageMemoryRequirements  = GetProcAddress(dll, "vkGetImageMemoryRequirements\0");
                _vkAllocateMemory              = GetProcAddress(dll, "vkAllocateMemory\0");
                _vkFreeMemory                  = GetProcAddress(dll, "vkFreeMemory\0");
                _vkBindImageMemory             = GetProcAddress(dll, "vkBindImageMemory\0");

                _vkCreateShaderModule          = GetProcAddress(dll, "vkCreateShaderModule\0");
                _vkDestroyShaderModule         = GetProcAddress(dll, "vkDestroyShaderModule\0");
                _vkCreateDescriptorSetLayout   = GetProcAddress(dll, "vkCreateDescriptorSetLayout\0");
                _vkDestroyDescriptorSetLayout  = GetProcAddress(dll, "vkDestroyDescriptorSetLayout\0");
                _vkCreatePipelineLayout        = GetProcAddress(dll, "vkCreatePipelineLayout\0");
                _vkDestroyPipelineLayout       = GetProcAddress(dll, "vkDestroyPipelineLayout\0");
                _vkCreateComputePipelines      = GetProcAddress(dll, "vkCreateComputePipelines\0");
                _vkDestroyPipeline             = GetProcAddress(dll, "vkDestroyPipeline\0");
                _vkCreateDescriptorPool        = GetProcAddress(dll, "vkCreateDescriptorPool\0");
                _vkDestroyDescriptorPool       = GetProcAddress(dll, "vkDestroyDescriptorPool\0");
                _vkAllocateDescriptorSets      = GetProcAddress(dll, "vkAllocateDescriptorSets\0");
                _vkUpdateDescriptorSets        = GetProcAddress(dll, "vkUpdateDescriptorSets\0");

                _vkCreateCommandPool           = GetProcAddress(dll, "vkCreateCommandPool\0");
                _vkDestroyCommandPool          = GetProcAddress(dll, "vkDestroyCommandPool\0");
                _vkAllocateCommandBuffers      = GetProcAddress(dll, "vkAllocateCommandBuffers\0");
                _vkFreeCommandBuffers          = GetProcAddress(dll, "vkFreeCommandBuffers\0");
                _vkBeginCommandBuffer          = GetProcAddress(dll, "vkBeginCommandBuffer\0");
                _vkEndCommandBuffer            = GetProcAddress(dll, "vkEndCommandBuffer\0");
                _vkResetCommandBuffer          = GetProcAddress(dll, "vkResetCommandBuffer\0");
                _vkCmdPipelineBarrier          = GetProcAddress(dll, "vkCmdPipelineBarrier\0");
                _vkCmdBindPipeline             = GetProcAddress(dll, "vkCmdBindPipeline\0");
                _vkCmdBindDescriptorSets       = GetProcAddress(dll, "vkCmdBindDescriptorSets\0");
                _vkCmdPushConstants            = GetProcAddress(dll, "vkCmdPushConstants\0");
                _vkCmdDispatch                 = GetProcAddress(dll, "vkCmdDispatch\0");
                _vkCmdCopyImage                = GetProcAddress(dll, "vkCmdCopyImage\0");

                _vkCreateFence                 = GetProcAddress(dll, "vkCreateFence\0");
                _vkDestroyFence                = GetProcAddress(dll, "vkDestroyFence\0");
                _vkResetFences                 = GetProcAddress(dll, "vkResetFences\0");
                _vkWaitForFences               = GetProcAddress(dll, "vkWaitForFences\0");
                _vkCreateSemaphore             = GetProcAddress(dll, "vkCreateSemaphore\0");
                _vkDestroySemaphore            = GetProcAddress(dll, "vkDestroySemaphore\0");

                return dll;
            };

            // ============================================================================
            // VK MEMORY HELPER - find a suitable memory type index
            // ============================================================================

            def vk_find_memory_type(VkPhysicalDeviceMemoryProperties* props, u32 typeFilter, u32 propertyFlags) -> u32
            {
                u32 i;
                i = 0;
                while (i < props.memoryTypeCount)
                {
                    // Each memory type occupies 2 u32 slots: [propertyFlags, heapIndex]
                    u32 mtFlags = props.memoryTypeData[i * 2];
                    if (((typeFilter >> i) `& 1) == 1)
                    {
                        if ((mtFlags `& propertyFlags) == propertyFlags)
                        {
                            return i;
                        };
                    };
                    i++;
                };
                return 0xFFFFFFFF;
            };

            // ============================================================================
            // VK IMAGE HELPER - transition image layout via a pipeline barrier
            // ============================================================================

            def vk_transition_image_layout(VkCommandBuffer cmd, VkImage image,
                                           i32 oldLayout, i32 newLayout,
                                           u32 srcStage, u32 dstStage,
                                           u32 srcAccess, u32 dstAccess) -> void
            {
                VkImageMemoryBarrier barrier;
                barrier.sType               = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
                barrier.pNext               = STDLIB_GVP;
                barrier.srcAccessMask       = srcAccess;
                barrier.dstAccessMask       = dstAccess;
                barrier.oldLayout           = oldLayout;
                barrier.newLayout           = newLayout;
                barrier.srcQueueFamilyIndex = VK_SUBPASS_EXTERNAL;
                barrier.dstQueueFamilyIndex = VK_SUBPASS_EXTERNAL;
                barrier.image               = image;
                barrier.aspectMask          = VK_IMAGE_ASPECT_COLOR_BIT;
                barrier.baseMipLevel        = 0;
                barrier.levelCount          = 1;
                barrier.baseArrayLayer      = 0;
                barrier.layerCount          = 1;

                vkCmdPipelineBarrier(cmd,
                    srcStage, dstStage, 0,
                    0, STDLIB_GVP,
                    0, STDLIB_GVP,
                    1, @barrier);
                return;
            };

            // ============================================================================
            // VkContext - Wraps Vulkan instance, physical device, logical device,
            // queues, surface, and swapchain setup - mirroring GLContext.
            //
            // Usage:
            //   VkContext vkctx(win.handle, win.instance, width, height);
            //   // ... create command pools, pipelines, record and submit work ...
            //   vkctx.__exit();
            // ============================================================================

            object VkContext
            {
                VkInstance         instance;
                VkPhysicalDevice   physical_device;
                VkDevice           device;
                VkQueue            graphics_queue;
                VkQueue            present_queue;
                u32                graphics_family;
                u32                present_family;
                VkSurfaceKHR       surface;
                VkSwapchainKHR     swapchain;
                i32                swapchain_format;
                VkExtent2D         swapchain_extent;
                u32                swapchain_image_count;
                VkImage[8]         swapchain_images;
                VkImageView[8]     swapchain_views;

                def __init(HWND hwnd, HINSTANCE hinstance, u32 width, u32 height) -> this
                {
                    this.swapchain_image_count = 0;
                    this.graphics_family = 0xFFFFFFFF;
                    this.present_family  = 0xFFFFFFFF;

                    // ---- Instance ----
                    byte[2]* ext_names;
                    ext_names[0] = "VK_KHR_surface\0";
                    ext_names[1] = "VK_KHR_win32_surface\0";

                    VkApplicationInfo app_info;
                    app_info.sType              = VK_STRUCTURE_TYPE_APPLICATION_INFO;
                    app_info.pNext              = STDLIB_GVP;
                    app_info.pApplicationName   = "FluxVulkan\0";
                    app_info.applicationVersion = 1;
                    app_info.pEngineName        = "FluxEngine\0";
                    app_info.engineVersion      = 1;
                    app_info.apiVersion         = 0x00401000;

                    VkInstanceCreateInfo inst_ci;
                    inst_ci.sType                   = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
                    inst_ci.pNext                   = STDLIB_GVP;
                    inst_ci.flags                   = 0;
                    inst_ci.pApplicationInfo        = @app_info;
                    inst_ci.enabledLayerCount       = 0;
                    inst_ci.ppEnabledLayerNames     = STDLIB_GVP;
                    inst_ci.enabledExtensionCount   = 2;
                    inst_ci.ppEnabledExtensionNames = @ext_names[0];
                    vkCreateInstance(@inst_ci, STDLIB_GVP, @this.instance);

                    // ---- Surface ----
                    VkWin32SurfaceCreateInfoKHR surf_ci;
                    surf_ci.sType     = VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR;
                    surf_ci.pNext     = STDLIB_GVP;
                    surf_ci.flags     = 0;
                    surf_ci.hinstance = hinstance;
                    surf_ci.hwnd      = hwnd;
                    vkCreateWin32SurfaceKHR(this.instance, @surf_ci, STDLIB_GVP, @this.surface);

                    // ---- Physical device: pick first GPU ----
                    u32 gpu_count;
                    gpu_count = 0;
                    vkEnumeratePhysicalDevices(this.instance, @gpu_count, STDLIB_GVP);
                    VkPhysicalDevice[4] gpus;
                    vkEnumeratePhysicalDevices(this.instance, @gpu_count, @gpus[0]);
                    this.physical_device = gpus[0];

                    // ---- Find queue families ----
                    u32 qf_count;
                    qf_count = 0;
                    vkGetPhysicalDeviceQueueFamilyProperties(this.physical_device, @qf_count, STDLIB_GVP);
                    VkQueueFamilyProperties[16] qf_props;
                    vkGetPhysicalDeviceQueueFamilyProperties(this.physical_device, @qf_count, @qf_props[0]);

                    u32 qi;
                    qi = 0;
                    while (qi < qf_count)
                    {
                        if ((qf_props[qi].queueFlags `& (u32)VK_QUEUE_GRAPHICS_BIT) != 0)
                        {
                            if (this.graphics_family == 0xFFFFFFFF)
                            {
                                this.graphics_family = qi;
                            };
                        };
                        VkBool32 present_support;
                        present_support = 0;
                        vkGetPhysicalDeviceSurfaceSupportKHR(this.physical_device, qi, this.surface, @present_support);
                        if (present_support != 0)
                        {
                            if (this.present_family == 0xFFFFFFFF)
                            {
                                this.present_family = qi;
                            };
                        };
                        qi++;
                    };

                    // ---- Logical device ----
                    float queue_priority;
                    queue_priority = 1.0;

                    VkDeviceQueueCreateInfo[2] q_ci;
                    q_ci[0].sType            = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
                    q_ci[0].pNext            = STDLIB_GVP;
                    q_ci[0].flags            = 0;
                    q_ci[0].queueFamilyIndex = this.graphics_family;
                    q_ci[0].queueCount       = 1;
                    q_ci[0].pQueuePriorities = @queue_priority;

                    u32 num_queues;
                    num_queues = 1;
                    if (this.present_family != this.graphics_family)
                    {
                        q_ci[1].sType            = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
                        q_ci[1].pNext            = STDLIB_GVP;
                        q_ci[1].flags            = 0;
                        q_ci[1].queueFamilyIndex = this.present_family;
                        q_ci[1].queueCount       = 1;
                        q_ci[1].pQueuePriorities = @queue_priority;
                        num_queues = 2;
                    };

                    byte[1]* dev_ext_names;
                    dev_ext_names[0] = "VK_KHR_swapchain\0";

                    VkDeviceCreateInfo dev_ci;
                    dev_ci.sType                   = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
                    dev_ci.pNext                   = STDLIB_GVP;
                    dev_ci.flags                   = 0;
                    dev_ci.queueCreateInfoCount    = num_queues;
                    dev_ci.pQueueCreateInfos       = @q_ci[0];
                    dev_ci.enabledLayerCount       = 0;
                    dev_ci.ppEnabledLayerNames     = STDLIB_GVP;
                    dev_ci.enabledExtensionCount   = 1;
                    dev_ci.ppEnabledExtensionNames = @dev_ext_names[0];
                    dev_ci.pEnabledFeatures        = STDLIB_GVP;
                    vkCreateDevice(this.physical_device, @dev_ci, STDLIB_GVP, @this.device);

                    vkGetDeviceQueue(this.device, this.graphics_family, 0, @this.graphics_queue);
                    vkGetDeviceQueue(this.device, this.present_family,  0, @this.present_queue);

                    // ---- Swapchain ----
                    VkSurfaceCapabilitiesKHR caps;
                    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(this.physical_device, this.surface, @caps);

                    this.swapchain_extent = caps.currentExtent;
                    if (this.swapchain_extent.width == 0xFFFFFFFF)
                    {
                        this.swapchain_extent.width  = width;
                        this.swapchain_extent.height = height;
                    };

                    u32 fmt_count;
                    fmt_count = 0;
                    vkGetPhysicalDeviceSurfaceFormatsKHR(this.physical_device, this.surface, @fmt_count, STDLIB_GVP);
                    VkSurfaceFormatKHR[16] surf_fmts;
                    vkGetPhysicalDeviceSurfaceFormatsKHR(this.physical_device, this.surface, @fmt_count, @surf_fmts[0]);

                    this.swapchain_format = VK_FORMAT_B8G8R8A8_UNORM;
                    u32 fmi;
                    fmi = 0;
                    while (fmi < fmt_count)
                    {
                        if (surf_fmts[fmi].format == VK_FORMAT_B8G8R8A8_UNORM |
                            surf_fmts[fmi].format == VK_FORMAT_R8G8B8A8_UNORM)
                        {
                            this.swapchain_format = surf_fmts[fmi].format;
                            break;
                        };
                        fmi++;
                    };

                    u32 img_count;
                    img_count = caps.minImageCount + 1;
                    if (caps.maxImageCount > 0 & img_count > caps.maxImageCount)
                    {
                        img_count = caps.maxImageCount;
                    };

                    VkSwapchainCreateInfoKHR sc_ci;
                    sc_ci.sType                 = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
                    sc_ci.pNext                 = STDLIB_GVP;
                    sc_ci.flags                 = 0;
                    sc_ci.surface               = this.surface;
                    sc_ci.minImageCount         = img_count;
                    sc_ci.imageFormat           = this.swapchain_format;
                    sc_ci.imageColorSpace       = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
                    sc_ci.imageExtent           = this.swapchain_extent;
                    sc_ci.imageArrayLayers      = 1;
                    sc_ci.imageUsage            = (u32)VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | (u32)VK_IMAGE_USAGE_TRANSFER_DST_BIT;
                    sc_ci.imageSharingMode      = VK_SHARING_MODE_EXCLUSIVE;
                    sc_ci.queueFamilyIndexCount = 0;
                    sc_ci.pQueueFamilyIndices   = STDLIB_GVP;
                    sc_ci.preTransform          = caps.currentTransform;
                    sc_ci.compositeAlpha        = (u32)VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
                    sc_ci.presentMode           = VK_PRESENT_MODE_FIFO_KHR;
                    sc_ci.clipped               = 1;
                    sc_ci.oldSwapchain          = (VkSwapchainKHR)0;
                    vkCreateSwapchainKHR(this.device, @sc_ci, STDLIB_GVP, @this.swapchain);

                    // ---- Swapchain images and views ----
                    vkGetSwapchainImagesKHR(this.device, this.swapchain, @this.swapchain_image_count, STDLIB_GVP);
                    if (this.swapchain_image_count > 8) { this.swapchain_image_count = 8; };
                    vkGetSwapchainImagesKHR(this.device, this.swapchain, @this.swapchain_image_count, @this.swapchain_images[0]);

                    u32 vi;
                    vi = 0;
                    while (vi < this.swapchain_image_count)
                    {
                        VkImageViewCreateInfo iv_ci;
                        iv_ci.sType          = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
                        iv_ci.pNext          = STDLIB_GVP;
                        iv_ci.flags          = 0;
                        iv_ci.image          = this.swapchain_images[vi];
                        iv_ci.viewType       = VK_IMAGE_VIEW_TYPE_2D;
                        iv_ci.format         = this.swapchain_format;
                        iv_ci.components_r   = 0;
                        iv_ci.components_g   = 0;
                        iv_ci.components_b   = 0;
                        iv_ci.components_a   = 0;
                        iv_ci.aspectMask     = (u32)VK_IMAGE_ASPECT_COLOR_BIT;
                        iv_ci.baseMipLevel   = 0;
                        iv_ci.levelCount     = 1;
                        iv_ci.baseArrayLayer = 0;
                        iv_ci.layerCount     = 1;
                        vkCreateImageView(this.device, @iv_ci, STDLIB_GVP, @this.swapchain_views[vi]);
                        vi++;
                    };

                    return this;
                };

                def __exit() -> void
                {
                    vkDeviceWaitIdle(this.device);

                    u32 vi;
                    vi = 0;
                    while (vi < this.swapchain_image_count)
                    {
                        vkDestroyImageView(this.device, this.swapchain_views[vi], STDLIB_GVP);
                        vi++;
                    };

                    vkDestroySwapchainKHR(this.device, this.swapchain, STDLIB_GVP);
                    vkDestroySurfaceKHR(this.instance, this.surface, STDLIB_GVP);
                    vkDestroyDevice(this.device, STDLIB_GVP);
                    vkDestroyInstance(this.instance, STDLIB_GVP);
                    return;
                };
            };
        };
    };
};

#endif;