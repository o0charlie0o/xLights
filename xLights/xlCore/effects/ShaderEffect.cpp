/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "ShaderEffect.h"
#include "../RenderContext.h"
#include "../Sequence.h"
#include "../StringUtils.h"

#include <algorithm>
#include <fstream>
#include <sstream>
#include <cctype>

namespace xlCore {

// ============================================================================
// Static Member Initialization
// ============================================================================

ShaderRenderer::Factory ShaderRenderer::s_factory = nullptr;
bool ShaderEffect::s_useBackgroundRender = true;

void ShaderRenderer::setFactory(Factory factory) {
    s_factory = std::move(factory);
}

std::unique_ptr<ShaderRenderer> ShaderRenderer::create() {
    if (s_factory) {
        return s_factory();
    }
    return nullptr;
}

// ============================================================================
// ShaderConfig Implementation
// ============================================================================

bool ShaderConfig::loadFromFile(const std::string& filename) {
    std::ifstream file(filename);
    if (!file.is_open()) {
        return false;
    }

    std::stringstream buffer;
    buffer << file.rdbuf();
    std::string code = buffer.str();

    m_filename = filename;

    // Look for JSON metadata in comments
    // Format: /*{...}*/ at the start or // { } style
    std::string json;

    // Try /* */ style JSON
    size_t jsonStart = code.find("/*{");
    if (jsonStart != std::string::npos) {
        size_t jsonEnd = code.find("}*/", jsonStart);
        if (jsonEnd != std::string::npos) {
            json = code.substr(jsonStart + 2, jsonEnd - jsonStart - 1);
        }
    }

    return loadFromString(code, json);
}

bool ShaderConfig::loadFromString(const std::string& code, const std::string& json) {
    m_code = code;

    // Check for standard uniforms in code
    m_hasRendersize = (code.find("RENDERSIZE") != std::string::npos);
    m_hasTime = (code.find("TIME") != std::string::npos);
    m_hasCoord = (code.find("isf_FragNormCoord") != std::string::npos ||
                  code.find("gl_FragCoord") != std::string::npos);

    // Check for canvas mode (uses input image)
    m_canvasMode = (code.find("inputImage") != std::string::npos);

    // Check for audio modes
    m_audioFFTMode = (code.find("audioFFT") != std::string::npos);
    m_audioIntensityMode = (code.find("audioIntensity") != std::string::npos);

    // Parse JSON metadata if present
    // This is a simplified parser - a real implementation would use a JSON library
    if (!json.empty()) {
        // Look for "DESCRIPTION"
        size_t descPos = json.find("\"DESCRIPTION\"");
        if (descPos != std::string::npos) {
            size_t valueStart = json.find('\"', descPos + 13);
            if (valueStart != std::string::npos) {
                size_t valueEnd = json.find('\"', valueStart + 1);
                if (valueEnd != std::string::npos) {
                    m_description = json.substr(valueStart + 1, valueEnd - valueStart - 1);
                }
            }
        }

        // Parse INPUTS array
        // This would need proper JSON parsing in a real implementation
        // For now, we'll rely on the platform layer to do detailed parsing
    }

    return !m_code.empty();
}

bool ShaderConfig::usesEvents() const {
    for (const auto& param : m_params) {
        if (param.type == ShaderParamType::Event) {
            return true;
        }
    }
    return false;
}

// ============================================================================
// ShaderEffect Implementation
// ============================================================================

ShaderEffect::ShaderEffect() = default;

std::vector<EffectParameter> ShaderEffect::parameters() const {
    std::vector<EffectParameter> params;

    // Shader file
    auto file = EffectParameter::createFile(
        "E_FILEPICKERCTRL_Shader",
        "Shader File",
        "Shader files|*.fs;*.glsl");
    file.group = "Shader";
    params.push_back(file);

    // Speed
    auto speed = EffectParameter::createInt(
        "E_SLIDER_Shader_Speed", "Speed", 100, SPEED_MIN, SPEED_MAX, true);
    speed.valueCurveDivisor = SPEED_DIVISOR;
    speed.group = "Animation";
    params.push_back(speed);

    // Time offset
    auto timeOffset = EffectParameter::createDouble(
        "E_TEXTCTRL_Shader_LeadIn", "Time Offset (s)", 0.0, 0.0, 1000.0, 0.1);
    timeOffset.group = "Animation";
    params.push_back(timeOffset);

    // Position offset
    auto offsetX = EffectParameter::createInt(
        "E_SLIDER_Shader_Offset_X", "X Offset", 0, OFFSET_MIN, OFFSET_MAX, true);
    offsetX.group = "Position";
    params.push_back(offsetX);

    auto offsetY = EffectParameter::createInt(
        "E_SLIDER_Shader_Offset_Y", "Y Offset", 0, OFFSET_MIN, OFFSET_MAX, true);
    offsetY.group = "Position";
    params.push_back(offsetY);

    // Zoom
    auto zoom = EffectParameter::createInt(
        "E_SLIDER_Shader_Zoom", "Zoom", 0, ZOOM_MIN, ZOOM_MAX, true);
    zoom.group = "Position";
    params.push_back(zoom);

    return params;
}

std::vector<std::string> ShaderEffect::fileReferences(const EffectSettings& settings) const {
    std::vector<std::string> refs;
    std::string file = settings.get("E_FILEPICKERCTRL_Shader");
    if (!file.empty()) {
        refs.push_back(file);
    }
    return refs;
}

bool ShaderEffect::isShaderFile(const std::string& path) {
    size_t dotPos = path.rfind('.');
    if (dotPos == std::string::npos) return false;

    std::string ext = path.substr(dotPos + 1);
    std::transform(ext.begin(), ext.end(), ext.begin(),
                   [](unsigned char c) { return std::tolower(c); });

    return (ext == "fs" || ext == "glsl" || ext == "frag");
}

std::unique_ptr<ShaderConfig> ShaderEffect::parseShader(const std::string& filename) {
    auto config = std::make_unique<ShaderConfig>();
    if (config->loadFromFile(filename)) {
        return config;
    }
    return nullptr;
}

bool ShaderEffect::canRenderOnBackgroundThread() const {
    return s_useBackgroundRender;
}

void ShaderEffect::render(RenderContext& ctx, const EffectSettings& settings, const RenderState& state) {
    // Initialize cache if needed
    if (!m_cache) {
        m_cache = std::make_unique<ShaderRenderCache>();
    }

    // Get parameters
    std::string filename = settings.get("E_FILEPICKERCTRL_Shader");
    double speed = settings.getDouble("E_SLIDER_Shader_Speed", 100.0) / SPEED_DIVISOR;
    double timeOffset = settings.getDouble("E_TEXTCTRL_Shader_LeadIn", 0.0);
    double offsetX = settings.getDouble("E_SLIDER_Shader_Offset_X", 0.0) / 100.0;
    double offsetY = settings.getDouble("E_SLIDER_Shader_Offset_Y", 0.0) / 100.0;
    double zoom = settings.getDouble("E_SLIDER_Shader_Zoom", 0.0) / 100.0;

    int bufferWi = state.bufferWidth;
    int bufferHt = state.bufferHeight;

    // Handle empty filename
    if (filename.empty()) {
        ctx.fill(Color::Red());
        return;
    }

    // Initialize or reinitialize on first frame or file change
    if (state.frameIndex == 0 || filename != m_cache->currentFile) {
        m_cache->reset();
        m_cache->currentFile = filename;

        // Parse shader
        m_cache->config = parseShader(filename);
        if (!m_cache->config) {
            ctx.fill(Color::Red());
            return;
        }

        // Create renderer
        m_cache->renderer = ShaderRenderer::create();
        if (!m_cache->renderer) {
            // No GPU renderer available - show indicator
            // In a real implementation, this would fall back to CPU rendering
            // or display a message that shaders are not supported
            ctx.fill(Color(128, 0, 128)); // Purple to indicate no GPU support
            return;
        }

        if (!m_cache->renderer->initialize(*m_cache->config)) {
            m_cache->renderer.reset();
            ctx.fill(Color::Red());
            return;
        }

        m_cache->renderer->setOutputSize(bufferWi, bufferHt);
    }

    if (!m_cache->renderer) {
        ctx.fill(Color(128, 0, 128)); // Purple - no renderer
        return;
    }

    // Calculate shader time
    double effectTime = state.timeSeconds - state.effectStartTime;
    float shaderTime = static_cast<float>(timeOffset + effectTime * speed);

    // Set standard uniforms
    m_cache->renderer->setTime(shaderTime);
    m_cache->renderer->setFrameIndex(state.frameIndex);
    m_cache->renderer->setUniformVec2("offset", static_cast<float>(offsetX), static_cast<float>(offsetY));
    m_cache->renderer->setUniformFloat("zoom", 1.0f + static_cast<float>(zoom));

    // Set shader-specific parameters from settings
    for (const auto& param : m_cache->config->params()) {
        std::string key = "E_SLIDER_SHADERXYZZY_" + param.name;
        if (settings.contains(key)) {
            float value = static_cast<float>(settings.getDouble(key, param.defaultValue));
            // Normalize to 0-1 range
            if (param.maxValue > param.minValue) {
                value = (value - static_cast<float>(param.minValue)) /
                        static_cast<float>(param.maxValue - param.minValue);
            }
            m_cache->renderer->setUniformFloat(param.name, value);
        }
    }

    // Render shader to ImageBuffer
    ImageBuffer output(bufferWi, bufferHt);
    if (m_cache->renderer->render(output)) {
        // Copy to render context
        for (int y = 0; y < bufferHt; y++) {
            for (int x = 0; x < bufferWi; x++) {
                Color c = output.getPixel(x, y);
                ctx.setPixel(x, y, c);
            }
        }
    } else {
        // Render failed
        ctx.fill(Color::Red());
    }
}

// Register the effect
XLCORE_REGISTER_EFFECT(ShaderEffect)

} // namespace xlCore
