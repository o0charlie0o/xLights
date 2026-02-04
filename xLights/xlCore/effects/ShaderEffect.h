/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#pragma once

/**
 * @file ShaderEffect.h
 * @brief GLSL/Metal shader effect for xlCore.
 *
 * This effect executes GLSL shader code to generate visual effects.
 * The actual GPU rendering is delegated to a platform-specific
 * ShaderRenderer implementation (OpenGL, Metal, etc.)
 *
 * Shader file format:
 * - Standard GLSL fragment shader syntax
 * - JSON metadata comment block for parameters
 * - Support for ShaderToy compatible shaders
 *
 * Required uniforms (automatically provided):
 * - TIME: Current time in seconds
 * - RENDERSIZE: Output resolution vec2(width, height)
 * - DATE: Current date as vec4(year, month, day, seconds)
 * - FRAMEINDEX: Current frame number
 * - PASSINDEX: Multipass index
 * - isf_FragNormCoord: Normalized fragment coordinate (0-1)
 *
 * NOTE: The actual shader execution requires a GPU context.
 * This class defines the interface; platform layer provides ShaderRenderer.
 */

#include "../Effect.h"
#include "../ImageBuffer.h"

#include <memory>
#include <string>
#include <vector>
#include <map>
#include <functional>

namespace xlCore {

// ============================================================================
// Shader Parameter Types
// ============================================================================

/**
 * @brief Types of shader parameters.
 */
enum class ShaderParamType {
    Image,       // Input image/texture
    Float,       // Floating point value
    Event,       // Timing event trigger
    Color,       // RGB color
    Bool,        // Boolean toggle
    Point2D,     // 2D point (vec2)
    Long,        // Integer value
    LongChoice,  // Integer from dropdown
    Audio,       // Audio intensity data
    AudioFFT     // Audio FFT data
};

/**
 * @brief A single shader parameter definition.
 */
struct ShaderParam {
    std::string name;
    std::string label;
    ShaderParamType type = ShaderParamType::Float;

    // For numeric types
    double minValue = 0.0;
    double maxValue = 1.0;
    double defaultValue = 0.5;

    // For Point2D types
    double minX = 0.0, minY = 0.0;
    double maxX = 1.0, maxY = 1.0;
    double defaultX = 0.5, defaultY = 0.5;

    // For choice types
    std::map<int, std::string> choices;

    std::string getLabel() const { return label.empty() ? name : label; }
    bool showInUI() const {
        return type == ShaderParamType::Float ||
               type == ShaderParamType::Bool ||
               type == ShaderParamType::LongChoice ||
               type == ShaderParamType::Event ||
               type == ShaderParamType::Point2D;
    }
};

/**
 * @brief Shader pass definition for multi-pass shaders.
 */
struct ShaderPass {
    std::string target;     // Target buffer name (empty = output)
    bool persistent = false; // Keep buffer between frames
};

/**
 * @brief Parsed shader configuration.
 */
class ShaderConfig {
public:
    ShaderConfig() = default;

    /**
     * @brief Parse shader from file.
     *
     * @param filename Path to shader file
     * @return true if parsing succeeded
     */
    bool loadFromFile(const std::string& filename);

    /**
     * @brief Parse shader from code string.
     *
     * @param code GLSL code
     * @param json JSON metadata
     * @return true if parsing succeeded
     */
    bool loadFromString(const std::string& code, const std::string& json);

    // Accessors
    const std::string& filename() const { return m_filename; }
    const std::string& description() const { return m_description; }
    const std::string& code() const { return m_code; }
    const std::vector<ShaderParam>& params() const { return m_params; }
    const std::vector<ShaderPass>& passes() const { return m_passes; }

    bool isCanvasShader() const { return m_canvasMode; }
    bool isAudioFFTShader() const { return m_audioFFTMode; }
    bool isAudioIntensityShader() const { return m_audioIntensityMode; }
    bool hasRendersize() const { return m_hasRendersize; }
    bool hasTime() const { return m_hasTime; }
    bool hasCoord() const { return m_hasCoord; }
    bool usesEvents() const;

private:
    std::string m_filename;
    std::string m_description;
    std::string m_code;
    std::vector<ShaderParam> m_params;
    std::vector<ShaderPass> m_passes;

    bool m_canvasMode = false;
    bool m_audioFFTMode = false;
    bool m_audioIntensityMode = false;
    bool m_hasRendersize = false;
    bool m_hasTime = false;
    bool m_hasCoord = false;
};

// ============================================================================
// Abstract Shader Renderer Interface
// ============================================================================

/**
 * @brief Abstract interface for GPU shader rendering.
 *
 * Platform layer must provide an implementation of this interface.
 * The implementation handles all GPU context management.
 */
class ShaderRenderer {
public:
    virtual ~ShaderRenderer() = default;

    /**
     * @brief Initialize the renderer for a shader.
     *
     * @param config Parsed shader configuration
     * @return true if initialization succeeded
     */
    virtual bool initialize(const ShaderConfig& config) = 0;

    /**
     * @brief Set output size.
     */
    virtual void setOutputSize(int width, int height) = 0;

    /**
     * @brief Set a float uniform value.
     */
    virtual void setUniformFloat(const std::string& name, float value) = 0;

    /**
     * @brief Set a vec2 uniform value.
     */
    virtual void setUniformVec2(const std::string& name, float x, float y) = 0;

    /**
     * @brief Set a vec4 uniform value.
     */
    virtual void setUniformVec4(const std::string& name, float x, float y, float z, float w) = 0;

    /**
     * @brief Set a color uniform value.
     */
    virtual void setUniformColor(const std::string& name, const Color& color) = 0;

    /**
     * @brief Set time uniform.
     */
    virtual void setTime(float seconds) = 0;

    /**
     * @brief Set frame index uniform.
     */
    virtual void setFrameIndex(int frame) = 0;

    /**
     * @brief Render to an ImageBuffer.
     *
     * @param output Output buffer to render to
     * @return true if rendering succeeded
     */
    virtual bool render(ImageBuffer& output) = 0;

    /**
     * @brief Release GPU resources.
     */
    virtual void cleanup() = 0;

    // ========== Factory ==========

    using Factory = std::function<std::unique_ptr<ShaderRenderer>()>;
    static void setFactory(Factory factory);
    static std::unique_ptr<ShaderRenderer> create();

private:
    static Factory s_factory;
};

// ============================================================================
// Shader Effect
// ============================================================================

/**
 * @brief Render cache for Shader effect.
 */
class ShaderRenderCache {
public:
    ShaderRenderCache() = default;
    ~ShaderRenderCache() = default;

    std::unique_ptr<ShaderConfig> config;
    std::unique_ptr<ShaderRenderer> renderer;
    std::string currentFile;

    void reset() {
        renderer.reset();
        config.reset();
        currentFile.clear();
    }
};

/**
 * @brief GLSL shader effect.
 *
 * Executes GLSL shaders for visual effect generation.
 * Actual GPU rendering is delegated to ShaderRenderer.
 */
class ShaderEffect : public Effect {
public:
    ShaderEffect();
    ~ShaderEffect() override = default;

    // ========== Identity ==========
    std::string name() const override { return "Shader"; }
    std::string description() const override { return "Run GLSL shaders for effects"; }
    std::string category() const override { return "Media"; }

    // ========== Rendering ==========
    void render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) override;

    // ========== Capabilities ==========
    bool canBeRandom() const override { return false; }
    bool appropriateOnNodes() const override { return false; }
    bool supportsRenderCache(const EffectSettings& settings) const override { return true; }
    bool canRenderOnBackgroundThread() const override;

    // ========== Parameters ==========
    std::vector<EffectParameter> parameters() const override;

    // ========== File References ==========
    std::vector<std::string> fileReferences(const EffectSettings& settings) const override;

    // ========== Cloning ==========
    std::unique_ptr<Effect> clone() const override {
        return std::make_unique<ShaderEffect>(*this);
    }

    // ========== Constants ==========
    static constexpr int SPEED_MIN = -1000;
    static constexpr int SPEED_MAX = 1000;
    static constexpr int SPEED_DIVISOR = 100;
    static constexpr int OFFSET_MIN = -100;
    static constexpr int OFFSET_MAX = 100;
    static constexpr int ZOOM_MIN = -100;
    static constexpr int ZOOM_MAX = 100;

    // ========== Utility ==========

    /**
     * @brief Check if file is a shader file.
     */
    static bool isShaderFile(const std::string& path);

    /**
     * @brief Parse a shader file.
     */
    static std::unique_ptr<ShaderConfig> parseShader(const std::string& filename);

private:
    mutable std::unique_ptr<ShaderRenderCache> m_cache;
    static bool s_useBackgroundRender;
};

} // namespace xlCore
