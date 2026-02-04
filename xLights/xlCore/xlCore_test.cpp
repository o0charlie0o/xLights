/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

/**
 * @file xlCore_test.cpp
 * @brief Compile-time and runtime tests for xlCore library.
 *
 * This file serves as both a compilation test and a unit test suite
 * for the xlCore library types.
 */

#include "xlCore.h"
#include <cassert>
#include <cmath>
#include <iostream>

using namespace xlCore;

// Color tests
void testColor() {
    // Default constructor
    Color c1;
    assert(c1.red == 0 && c1.green == 0 && c1.blue == 0 && c1.alpha == 255);

    // RGB constructor
    Color c2(255, 128, 64);
    assert(c2.red == 255 && c2.green == 128 && c2.blue == 64);

    // RGBA constructor
    Color c3(100, 150, 200, 128);
    assert(c3.alpha == 128);

    // Equality (alpha not compared)
    Color c4(255, 128, 64);
    assert(c2 == c4);

    // Packed RGB
    uint32_t rgb = c2.getRGB(false); // RRGGBB order
    assert(rgb == 0xFF8040);

    // From packed RGB
    Color c5(0xFF8040u, false);
    assert(c5 == c2);

    // HSV round-trip
    Color red(255, 0, 0);
    HSV hsv = red.toHSV();
    assert(std::abs(hsv.hue) < 0.01 || std::abs(hsv.hue - 1.0) < 0.01);
    assert(std::abs(hsv.saturation - 1.0) < 0.01);
    assert(std::abs(hsv.value - 1.0) < 0.01);

    Color fromHsv(hsv);
    assert(fromHsv.red > 250); // Allow small rounding error

    // HSL round-trip
    Color blue(0, 0, 255);
    HSL hsl = blue.toHSL();
    Color fromHsl(hsl);
    assert(fromHsl.blue > 250);

    // String conversion
    Color strColor("#FF8040");
    assert(strColor == c2);

    std::string str = c2.toString();
    assert(str == "#ff8040");

    // Alpha blend
    Color white(255, 255, 255);
    Color blackTransparent(0, 0, 0, 128);
    Color blended = blackTransparent.alphaBlend(white);
    assert(blended.red > 100 && blended.red < 150);

    // Predefined colors
    assert(Color::Red().red == 255);
    assert(Color::Green().green == 255);
    assert(Color::Blue().blue == 255);

    std::cout << "Color tests passed!" << std::endl;
}

// Math types tests
void testMath() {
    // Point2D
    Point2D p1(10, 20);
    Point2D p2(5, 10);
    Point2D sum = p1 + p2;
    assert(sum.x == 15 && sum.y == 30);

    // Vec2
    Vec2 v1(3.0f, 4.0f);
    assert(std::abs(v1.length() - 5.0f) < 0.001f);

    Vec2 v2(1.0f, 0.0f);
    Vec2 v3(0.0f, 1.0f);
    assert(std::abs(v2.dot(v3)) < 0.001f); // Perpendicular
    assert(std::abs(v2.cross(v3) - 1.0f) < 0.001f);

    Vec2 normalized = v1.normalized();
    assert(std::abs(normalized.length() - 1.0f) < 0.001f);

    // Vec3
    Vec3 va(1.0f, 0.0f, 0.0f);
    Vec3 vb(0.0f, 1.0f, 0.0f);
    Vec3 cross = va.cross(vb);
    assert(std::abs(cross.z - 1.0f) < 0.001f);

    // Rect
    Rect r1(10, 20, 100, 50);
    assert(r1.contains(50, 40));
    assert(!r1.contains(5, 40));
    assert(r1.right() == 110);
    assert(r1.bottom() == 70);

    Rect r2(50, 40, 100, 50);
    assert(r1.intersects(r2));

    Rect intersection = r1.intersection(r2);
    assert(intersection.x == 50 && intersection.width == 60);

    // Math utilities
    assert(std::abs(math::toRadians(180.0f) - math::PI) < 0.001f);
    assert(std::abs(math::toDegrees(math::PI) - 180.0f) < 0.001f);
    assert(math::clamp(5, 0, 10) == 5);
    assert(math::clamp(-5, 0, 10) == 0);
    assert(math::clamp(15, 0, 10) == 10);

    std::cout << "Math tests passed!" << std::endl;
}

// ImageBuffer tests
void testImageBuffer() {
    ImageBuffer buf(100, 50);
    assert(buf.width() == 100);
    assert(buf.height() == 50);
    assert(buf.pixelCount() == 5000);

    buf.clear(Color::Red());
    Color pixel = buf.getPixel(50, 25);
    assert(pixel.red == 255 && pixel.green == 0 && pixel.blue == 0);

    buf.setPixel(10, 10, Color::Green());
    pixel = buf.getPixel(10, 10);
    assert(pixel.green == 255);

    // Fill rect
    buf.fillRect(20, 20, 10, 10, Color::Blue());
    pixel = buf.getPixel(25, 25);
    assert(pixel.blue == 255);

    // Copy region
    ImageBuffer buf2(50, 50);
    buf2.clear(Color::White());
    buf2.copyRegion(buf, 20, 20, 0, 0, 10, 10);
    pixel = buf2.getPixel(5, 5);
    assert(pixel.blue == 255);

    std::cout << "ImageBuffer tests passed!" << std::endl;
}

// Output protocol tests
void testOutput() {
    // OutputConfig
    OutputConfig config;
    config.name = "Test Output";
    config.enabled = true;
    config.channelCount = 512;
    config.startChannel = 1;
    config.setString("ip", "192.168.1.100");
    config.setInt("universe", 1);
    config.setBool("multicast", true);

    assert(config.getString("ip") == "192.168.1.100");
    assert(config.getInt("universe") == 1);
    assert(config.getBool("multicast") == true);
    assert(config.getString("nonexistent", "default") == "default");
    assert(config.getInt("nonexistent", 42) == 42);

    // OutputFactory
    auto protocols = OutputFactory::availableProtocols();
    assert(protocols.size() >= 5);
    assert(std::find(protocols.begin(), protocols.end(), "E131") != protocols.end());
    assert(std::find(protocols.begin(), protocols.end(), "ArtNet") != protocols.end());
    assert(std::find(protocols.begin(), protocols.end(), "DDP") != protocols.end());
    assert(std::find(protocols.begin(), protocols.end(), "DMX") != protocols.end());
    assert(std::find(protocols.begin(), protocols.end(), "NULL") != protocols.end());

    // Create NullOutput (the only one that works without hardware)
    auto nullOutput = OutputFactory::create("NULL");
    assert(nullOutput != nullptr);
    assert(nullOutput->protocolName() == "NULL");
    assert(nullOutput->isNetworkProtocol() == false);
    assert(nullOutput->maxChannels() == 2000000);

    // Test NullOutput lifecycle
    assert(!nullOutput->isOpen());
    assert(nullOutput->open());
    assert(nullOutput->isOpen());
    assert(nullOutput->statusString() == "Connected");

    // Test frame sending
    std::vector<uint8_t> frameData(512, 128);
    assert(nullOutput->sendFrame(frameData.data(), frameData.size()));
    assert(nullOutput->framesSent() == 1);
    assert(nullOutput->errors() == 0);

    nullOutput->close();
    assert(!nullOutput->isOpen());
    assert(nullOutput->statusString() == "Disconnected");

    // E131Output configuration
    auto e131 = OutputFactory::create("E131");
    assert(e131 != nullptr);
    assert(e131->protocolName() == "E131");
    assert(e131->isNetworkProtocol() == true);
    assert(e131->maxChannels() == 512);

    E131Output* e131Ptr = dynamic_cast<E131Output*>(e131.get());
    assert(e131Ptr != nullptr);
    e131Ptr->setUniverse(5);
    assert(e131Ptr->universe() == 5);
    e131Ptr->setPriority(150);
    assert(e131Ptr->priority() == 150);
    e131Ptr->setMulticast(false);
    assert(e131Ptr->isMulticast() == false);
    e131Ptr->setIP("192.168.1.200");
    assert(e131Ptr->ip() == "192.168.1.200");

    // ArtNetOutput configuration
    auto artnet = OutputFactory::create("ArtNet");
    assert(artnet != nullptr);
    assert(artnet->protocolName() == "ArtNet");

    ArtNetOutput* artnetPtr = dynamic_cast<ArtNetOutput*>(artnet.get());
    assert(artnetPtr != nullptr);
    artnetPtr->setUniverse(10);
    assert(artnetPtr->universe() == 10);

    // ArtNet universe breakdown
    assert(ArtNetOutput::getNet(0x1234) == 0x12);
    assert(ArtNetOutput::getSubnet(0x1234) == 0x03);
    assert(ArtNetOutput::getUniversePart(0x1234) == 0x04);
    assert(ArtNetOutput::combinedUniverse(0x12, 0x03, 0x04) == 0x1234);

    // DDPOutput configuration
    auto ddp = OutputFactory::create("DDP");
    assert(ddp != nullptr);
    assert(ddp->protocolName() == "DDP");
    assert(ddp->maxChannels() == 2000000);

    DDPOutput* ddpPtr = dynamic_cast<DDPOutput*>(ddp.get());
    assert(ddpPtr != nullptr);
    ddpPtr->setID(1);
    assert(ddpPtr->id() == 1);
    ddpPtr->setChannelsPerPacket(1000);
    assert(ddpPtr->channelsPerPacket() == 1000);

    // DMXOutput configuration
    auto dmx = OutputFactory::create("DMX");
    assert(dmx != nullptr);
    assert(dmx->protocolName() == "DMX");
    assert(dmx->isNetworkProtocol() == false);
    assert(dmx->isSerialProtocol() == true);
    assert(dmx->maxChannels() == 512);

    DMXOutput* dmxPtr = dynamic_cast<DMXOutput*>(dmx.get());
    assert(dmxPtr != nullptr);
    dmxPtr->setSerialPort("/dev/ttyUSB0");
    assert(dmxPtr->serialPort() == "/dev/ttyUSB0");
    dmxPtr->setBaudRate(250000);
    assert(dmxPtr->baudRate() == 250000);

    // OutputManager
    OutputManager manager;
    assert(manager.outputCount() == 0);

    auto null1 = std::make_unique<NullOutput>();
    OutputConfig null1Config;
    null1Config.name = "Null1";
    null1Config.channelCount = 512;
    null1Config.startChannel = 1;
    null1->configure(null1Config);
    manager.addOutput(std::move(null1));

    auto null2 = std::make_unique<NullOutput>();
    OutputConfig null2Config;
    null2Config.name = "Null2";
    null2Config.channelCount = 512;
    null2Config.startChannel = 513;
    null2->configure(null2Config);
    manager.addOutput(std::move(null2));

    assert(manager.outputCount() == 2);
    auto names = manager.outputNames();
    assert(names.size() == 2);

    assert(manager.getOutput("Null1") != nullptr);
    assert(manager.getOutput("Null2") != nullptr);
    assert(manager.getOutput("NonExistent") == nullptr);

    // Open all outputs
    assert(manager.openAll());

    // Send frame to all outputs
    std::vector<uint8_t> fullFrame(1024, 200);
    manager.startFrame(0);
    assert(manager.sendFrame(fullFrame.data(), fullFrame.size()));
    manager.endFrame();

    assert(manager.totalFramesSent() == 2);
    assert(manager.totalErrors() == 0);

    // All off
    manager.allOff();

    // Close all outputs
    manager.closeAll();

    // Remove output
    manager.removeOutput("Null1");
    assert(manager.outputCount() == 1);
    assert(manager.getOutput("Null1") == nullptr);

    // Unknown protocol returns nullptr
    auto unknown = OutputFactory::create("UNKNOWN");
    assert(unknown == nullptr);

    std::cout << "Output tests passed!" << std::endl;
}

// Effect tests
void testEffect() {
    // EffectSettings basic operations (using existing API from Sequence.h)
    EffectSettings settings;
    assert(settings.empty());

    // Use the existing set methods
    settings.setInt("int_param", 42);
    settings.setDouble("double_param", 3.14);
    settings.setBool("bool_param", true);
    settings.set("string_param", "hello");

    assert(settings.size() == 4);
    assert(!settings.empty());
    assert(settings.contains("int_param"));
    assert(!settings.contains("nonexistent"));

    // Use the existing get methods
    assert(settings.getInt("int_param") == 42);
    assert(settings.getInt("nonexistent", 99) == 99);
    assert(std::abs(settings.getDouble("double_param") - 3.14) < 0.001);
    assert(settings.getBool("bool_param") == true);
    assert(settings.get("string_param") == "hello");

    // EffectSettings remove
    settings.remove("int_param");
    assert(!settings.contains("int_param"));
    assert(settings.size() == 3);

    // EffectSettings clear
    settings.clear();
    assert(settings.empty());

    // EffectSettings toString/fromString serialization
    settings.set("key1", "value1");
    settings.set("key2", "value2");
    std::string serialized = settings.toString();
    assert(serialized.find("key1") != std::string::npos);
    assert(serialized.find("value1") != std::string::npos);

    auto parsed = EffectSettings::fromString(serialized);
    assert(parsed.get("key1") == "value1");
    assert(parsed.get("key2") == "value2");

    // EffectParameter factory methods
    auto intParam = EffectParameter::createInt("bar_count", "Bar Count", 10, 1, 100, true);
    assert(intParam.key == "bar_count");
    assert(intParam.displayName == "Bar Count");
    assert(intParam.type == ParameterType::Int);
    assert(intParam.defaultValue == "10");
    assert(intParam.minValue == 1.0);
    assert(intParam.maxValue == 100.0);
    assert(intParam.supportsValueCurve == true);

    auto boolParam = EffectParameter::createBool("highlight", "Highlight", false);
    assert(boolParam.type == ParameterType::Bool);
    assert(boolParam.defaultValue == "0");

    auto choiceParam = EffectParameter::createChoice("direction", "Direction", "up",
        {"up", "down", "left", "right"});
    assert(choiceParam.type == ParameterType::Choice);
    assert(choiceParam.choices.size() == 4);

    auto colorParam = EffectParameter::createColor("color1", "Color 1", Color::Blue());
    assert(colorParam.type == ParameterType::Color);

    // RenderState
    RenderState state;
    state.effectStartTime = 0.0;
    state.effectEndTime = 10.0;
    state.timeSeconds = 5.0;
    state.updateProgress();
    assert(std::abs(state.progress - 0.5) < 0.001);

    // EffectRegistry singleton
    EffectRegistry& registry = EffectRegistry::instance();
    // Registry is empty until effects are registered
    auto names = registry.effectNames();
    // Just verify we can call it - may be empty or have effects from other tests

    std::cout << "Effect tests passed!" << std::endl;
}

// String utilities tests
void testStringUtils() {
    using namespace strings;

    // Trim
    assert(trim("  hello  ") == "hello");
    assert(trimLeft("  hello") == "hello");
    assert(trimRight("hello  ") == "hello");

    // Case conversion
    assert(toLower("Hello World") == "hello world");
    assert(toUpper("Hello World") == "HELLO WORLD");
    assert(equalsIgnoreCase("Hello", "HELLO"));

    // Prefix/suffix
    assert(startsWith("hello world", "hello"));
    assert(endsWith("hello world", "world"));
    assert(contains("hello world", "lo wo"));

    // Split/join
    auto parts = split("a,b,c", ',');
    assert(parts.size() == 3);
    assert(parts[1] == "b");

    std::string joined = join(parts, "-");
    assert(joined == "a-b-c");

    // Replace
    assert(replaceAll("hello hello", "hello", "hi") == "hi hi");

    // Parse
    assert(parseInt("42") == 42);
    assert(parseInt("invalid", -1) == -1);
    assert(parseDouble("3.14").value_or(0.0) > 3.13);
    assert(parseBool("true") == true);
    assert(parseBool("yes") == true);
    assert(parseBool("0") == false);

    // Format
    assert(format("Hello %d", 42) == "Hello 42");

    // URL encode/decode
    assert(urlEncode("hello world") == "hello+world");
    assert(urlDecode("hello+world") == "hello world");

    // XML escape
    assert(escapeXml("<tag>") == "&lt;tag&gt;");

    std::cout << "StringUtils tests passed!" << std::endl;
}

int main() {
    std::cout << "xlCore library version: " << xlCore::version() << std::endl;
    std::cout << "Running tests..." << std::endl;

    testColor();
    testMath();
    testImageBuffer();
    testOutput();
    testEffect();
    testStringUtils();

    std::cout << "\nAll tests passed!" << std::endl;
    return 0;
}
