/***************************************************************
 * This source files comes from the xLights project
 * https://www.xlights.org
 * https://github.com/xLightsSequencer/xLights
 * See the github commit history for a record of contributing
 * developers.
 * Copyright claimed based on commit dates recorded in Github
 * License: https://github.com/xLightsSequencer/xLights/blob/master/License.txt
 **************************************************************/

#include "ModelEngine.h"

#ifdef XLIGHTS_NATIVE
#include "../native-mac/providers/NativeModelProvider.h"
#endif

#ifndef XLIGHTS_NATIVE
#include "adapters/ModelManagerAdapter.h"

#include <algorithm>

#include "../models/Model.h"
#include "../models/ModelManager.h"
#include "../models/ModelGroup.h"
#include "../models/SubModel.h"
#include "../models/Node.h"
#include "../models/BaseObject.h"

#include <wx/xml/xml.h>
#endif

#include <algorithm>
#include <cmath>
#include <set>
#include <sstream>

namespace xlEngine {

#ifdef XLIGHTS_NATIVE
// Native build: implementation using IModelProvider's stored XML attributes

// Helper to safely parse a float attribute with a default value
static float attrFloat(const std::map<std::string, std::string>& attrs,
                       const std::string& key, float defaultVal = 0.0f) {
    auto it = attrs.find(key);
    if (it == attrs.end() || it->second.empty()) return defaultVal;
    try { return std::stof(it->second); }
    catch (...) { return defaultVal; }
}

// Helper to safely parse an int attribute with a default value
static int attrInt(const std::map<std::string, std::string>& attrs,
                   const std::string& key, int defaultVal = 0) {
    auto it = attrs.find(key);
    if (it == attrs.end() || it->second.empty()) return defaultVal;
    try { return std::stoi(it->second); }
    catch (...) { return defaultVal; }
}

// Helper to get a string attribute with a default
static std::string attrStr(const std::map<std::string, std::string>& attrs,
                           const std::string& key, const std::string& defaultVal = "") {
    auto it = attrs.find(key);
    return (it != attrs.end()) ? it->second : defaultVal;
}

// Determine channels per node from the StringType XML attribute.
// Mirrors the logic from Model::GetNodeChannelCount().
static uint32_t channelsPerNodeFromStringType(const std::string& stringType)
{
    if (stringType.empty()) return 3; // Default RGB

    if (stringType.find("Single Color") == 0) return 1;
    if (stringType == "Strobes White 3fps" || stringType == "Strobes") return 1;
    if (stringType == "Node Single Color") return 1;
    if (stringType == "RGBWW Nodes") return 5;
    if (stringType == "4 Channel RGBW" || stringType == "4 Channel WRGB") return 4;

    // Various WRGB/RGBW variants: check for 'W' at position 0 or 3
    if (stringType.size() >= 4) {
        if (stringType[0] == 'W' || stringType[3] == 'W') return 4;
    }

    return 3; // Default: RGB Nodes, GRB Nodes, etc.
}

// Parse a StartChannel string and return the 0-indexed absolute channel number.
// Handles simple numeric values. For complex references (">Model:N", "@Model:N",
// "!Controller:N"), returns -1 to indicate it cannot be resolved without a model graph.
static int32_t parseStartChannelSimple(const std::string& startChannel)
{
    if (startChannel.empty()) return 0;

    // Check for complex references
    if (startChannel.find(':') != std::string::npos ||
        startChannel[0] == '>' || startChannel[0] == '<' ||
        startChannel[0] == '@' || startChannel[0] == '!') {
        return -1; // Cannot resolve without model graph
    }

    try {
        int32_t ch = std::stoi(startChannel);
        return (ch > 0) ? ch - 1 : 0; // Convert from 1-indexed to 0-indexed
    } catch (...) {
        return 0;
    }
}

// Generate node positions for a model from its XML attributes.
// This approximates the legacy Model class node generation using only the
// attributes stored in rgbeffects.xml — no Model objects required.
std::vector<NodeCoord> generateNodesFromAttributes(
    const std::map<std::string, std::string>& attrs)
{
    std::string type = attrStr(attrs, "DisplayAs");
    float wx = attrFloat(attrs, "WorldPosX");
    float wy = attrFloat(attrs, "WorldPosY");
    float wz = attrFloat(attrs, "WorldPosZ");

    int parm1 = attrInt(attrs, "parm1", 1);
    int parm2 = attrInt(attrs, "parm2", 1);
    int parm3 = attrInt(attrs, "parm3", 1);
    if (parm1 < 1) parm1 = 1;
    if (parm2 < 1) parm2 = 1;
    if (parm3 < 1) parm3 = 1;

    // Two-point models (SingleLine, Arches, etc.) define extent via X2/Y2
    // These are OFFSETS from WorldPos in the legacy code.
    float x2 = attrFloat(attrs, "X2");
    float y2 = attrFloat(attrs, "Y2");
    float z2 = attrFloat(attrs, "Z2");

    // Three-point models (Matrix, Image) add a height vector
    float x3 = attrFloat(attrs, "X3");
    float y3 = attrFloat(attrs, "Y3");

    std::vector<NodeCoord> nodes;

    if (type == "SingleLine" || type == "Single Line") {
        // Nodes along a line from WorldPos to WorldPos + (X2, Y2, Z2)
        int totalNodes = parm1 * parm2;
        if (totalNodes < 1) totalNodes = 1;
        nodes.reserve(totalNodes);
        for (int i = 0; i < totalNodes; i++) {
            float t = (totalNodes > 1) ? (float)i / (float)(totalNodes - 1) : 0.5f;
            NodeCoord nc;
            nc.x = wx + x2 * t;
            nc.y = wy + y2 * t;
            nc.z = wz + z2 * t;
            nc.bufX = i;
            nc.bufY = 0;
            nodes.push_back(nc);
        }
    }
    else if (type == "Vert Matrix" || type == "Horiz Matrix" || type == "Matrix") {
        // Grid layout: parm1 strings × parm2 nodes per string
        // parm3 = strands per string (zig-zag segments)
        int parm3 = attrInt(attrs, "parm3", 1);
        if (parm3 < 1) parm3 = 1;
        if (parm3 > parm2) parm3 = parm2;

        int numStrands = parm1 * parm3;
        int pixelsPerStrand = (parm3 > 0) ? parm2 / parm3 : parm2;

        // Wiring direction attributes
        std::string dirAttr = attrStr(attrs, "Dir");
        bool isLtoR = (dirAttr != "R"); // Dir="L" or missing → true
        std::string startSideAttr = attrStr(attrs, "StartSide");
        bool isBotToTop = (startSideAttr == "B"); // StartSide="B" → true
        std::string noZigStr = attrStr(attrs, "NoZig");
        bool noZig = (noZigStr == "true" || noZigStr == "1");

        bool isVert = (type == "Vert Matrix");
        int cols, rows;
        if (isVert) {
            cols = numStrands;       // strands across X
            rows = pixelsPerStrand;  // pixels along Y
        } else {
            cols = pixelsPerStrand;  // pixels along X
            rows = numStrands;       // strands along Y
        }
        if (cols < 1) cols = 1;
        if (rows < 1) rows = 1;

        bool hasThreePoint = (std::abs(x2) > 0.1f || std::abs(y2) > 0.1f ||
                              std::abs(x3) > 0.1f || std::abs(y3) > 0.1f);

        // Pre-read scale for boxed location case
        float scaleX = attrFloat(attrs, "ScaleX", 1.0f);
        float scaleY = attrFloat(attrs, "ScaleY", 1.0f);
        if (std::abs(scaleX) < 0.001f) scaleX = 1.0f;
        if (std::abs(scaleY) < 0.001f) scaleY = 1.0f;

        nodes.reserve(cols * rows);
        for (int r = 0; r < rows; r++) {
            for (int c = 0; c < cols; c++) {
                NodeCoord nc;

                // Buffer coordinates with zigzag, direction, and start side
                // Match xLights MatrixModel InitHMatrix/InitVMatrix logic
                if (isVert) {
                    // Vert Matrix: c = strand index (x), r = pixel in strand (y)
                    int segmentnum = c % parm3;
                    nc.bufX = isLtoR ? c : numStrands - c - 1;
                    if (noZig) {
                        nc.bufY = isBotToTop ? r : pixelsPerStrand - r - 1;
                    } else {
                        nc.bufY = (isBotToTop == (segmentnum % 2 == 0)) ? r : pixelsPerStrand - r - 1;
                    }
                } else {
                    // Horiz Matrix: r = strand index (y), c = pixel in strand (x)
                    int segmentnum = r % parm3;
                    nc.bufY = isBotToTop ? r : numStrands - r - 1;
                    if (noZig) {
                        nc.bufX = isLtoR ? c : pixelsPerStrand - c - 1;
                    } else {
                        nc.bufX = (isLtoR != (segmentnum % 2 == 0)) ? pixelsPerStrand - c - 1 : c;
                    }
                }

                // Screen position derived from buffer coords so physical layout matches buffer
                if (hasThreePoint) {
                    float ct = (cols > 1) ? (float)nc.bufX / (float)(cols - 1) : 0.5f;
                    float rt = (rows > 1) ? (float)nc.bufY / (float)(rows - 1) : 0.5f;
                    nc.x = wx + x2 * ct + x3 * rt;
                    nc.y = wy + y2 * ct + y3 * rt;
                    nc.z = wz + z2 * ct;
                } else {
                    nc.x = wx + ((float)nc.bufX - (float)(cols - 1) / 2.0f) * scaleX;
                    nc.y = wy + ((float)nc.bufY - (float)(rows - 1) / 2.0f) * scaleY;
                    nc.z = wz;
                }

                nodes.push_back(nc);
            }
        }
    }
    else if (type == "Arches") {
        // parm1 arches, parm2 nodes per arch
        int numArches = parm1;
        int nodesPerArch = parm2;
        if (numArches < 1) numArches = 1;
        if (nodesPerArch < 1) nodesPerArch = 1;
        float arcDeg = attrFloat(attrs, "arc", 180.0f);
        if (arcDeg <= 0) arcDeg = 180.0f;

        // The line from WorldPos to WorldPos+(X2,Y2) is the baseline
        float baseLen = std::sqrt(x2 * x2 + y2 * y2);
        if (baseLen < 1.0f) baseLen = 100.0f;
        float archSpacing = (numArches > 1) ? baseLen / numArches : 0.0f;

        // Direction along the baseline
        float dirX = (baseLen > 0) ? x2 / baseLen : 1.0f;
        float dirY = (baseLen > 0) ? y2 / baseLen : 0.0f;
        // Perpendicular (up)
        float perpX = -dirY;
        float perpY = dirX;

        nodes.reserve(numArches * nodesPerArch);
        for (int a = 0; a < numArches; a++) {
            float archCenter = (numArches > 1)
                ? (float)a / (float)(numArches - 1) * baseLen
                : baseLen * 0.5f;
            float cx = wx + dirX * archCenter;
            float cy = wy + dirY * archCenter;

            float radius = archSpacing * 0.45f;
            if (radius < 5.0f) radius = baseLen * 0.5f / numArches;

            float startAngle = (180.0f - arcDeg) / 2.0f;
            for (int n = 0; n < nodesPerArch; n++) {
                float t = (nodesPerArch > 1) ? (float)n / (float)(nodesPerArch - 1) : 0.5f;
                float angleDeg = startAngle + t * arcDeg;
                float angleRad = angleDeg * 3.14159265f / 180.0f;

                NodeCoord nc;
                nc.x = cx + dirX * radius * std::cos(angleRad)
                          + perpX * radius * std::sin(angleRad);
                nc.y = cy + dirY * radius * std::cos(angleRad)
                          + perpY * radius * std::sin(angleRad);
                nc.z = wz;
                nc.bufX = n;
                nc.bufY = a;
                nodes.push_back(nc);
            }
        }
    }
    else if (type == "Icicles" || type == "CandyCanes") {
        // ThreePointScreenLocation: baseline from WorldPos along X2/Y2, drops hanging down
        int numStrands = parm1;
        int nodesPerStrand = parm2;
        if (numStrands < 1) numStrands = 1;
        if (nodesPerStrand < 1) nodesPerStrand = 1;

        float baseLen = std::sqrt(x2 * x2 + y2 * y2);
        if (baseLen < 1.0f) baseLen = 100.0f;

        float dirX = x2 / baseLen;
        float dirY = y2 / baseLen;
        // Perpendicular direction (for hanging drops / cane hooks)
        float perpX = -dirY;
        float perpY = dirX;
        float height = attrFloat(attrs, "Height", 50.0f);
        if (height < 1.0f) height = 50.0f;

        nodes.reserve(numStrands * nodesPerStrand);
        for (int s = 0; s < numStrands; s++) {
            float st = (numStrands > 1) ? (float)s / (float)(numStrands - 1) : 0.5f;
            float sx = wx + x2 * st;
            float sy = wy + y2 * st;

            for (int n = 0; n < nodesPerStrand; n++) {
                float nt = (nodesPerStrand > 1) ? (float)n / (float)(nodesPerStrand - 1) : 1.0f;
                NodeCoord nc;
                nc.x = sx - perpX * height * nt;
                nc.y = sy - perpY * height * nt;
                nc.z = wz;
                nc.bufX = n;
                nc.bufY = s;
                nodes.push_back(nc);
            }
        }
    }
    else if (type == "Custom") {
        // Custom models define their pixel layout in the CustomModel or
        // CustomModelCompressed attribute. Only occupied cells get nodes.
        float scaleX = attrFloat(attrs, "ScaleX", 1.0f);
        float scaleY = attrFloat(attrs, "ScaleY", 1.0f);
        if (std::abs(scaleX) < 0.001f) scaleX = 1.0f;
        if (std::abs(scaleY) < 0.001f) scaleY = 1.0f;

        std::string compressedData = attrStr(attrs, "CustomModelCompressed");
        std::string customData = attrStr(attrs, "CustomModel");

        struct CellInfo { int col; int row; int nodeNum; };
        std::vector<CellInfo> cells;
        int gridWidth = 0, gridHeight = 0;

        if (!compressedData.empty()) {
            // Compressed format: "nodeNum,row,col[,layer];..."
            std::istringstream stream(compressedData);
            std::string entry;
            while (std::getline(stream, entry, ';')) {
                if (entry.empty()) continue;
                std::istringstream es(entry);
                std::string part;
                std::vector<int> parts;
                while (std::getline(es, part, ',')) {
                    try { parts.push_back(std::stoi(part)); }
                    catch (...) { parts.push_back(-1); }
                }
                if (parts.size() >= 3 && parts[0] > 0) {
                    cells.push_back({parts[2], parts[1], parts[0]});
                    gridWidth = std::max(gridWidth, parts[2] + 1);
                    gridHeight = std::max(gridHeight, parts[1] + 1);
                }
            }
        } else if (!customData.empty()) {
            // Standard format: rows by ";", cols by ",", layers by "|"
            // Parse first layer only
            std::string layerData = customData;
            size_t pipePos = layerData.find('|');
            if (pipePos != std::string::npos) {
                layerData = layerData.substr(0, pipePos);
            }

            std::istringstream rowStream(layerData);
            std::string rowStr;
            int row = 0;
            while (std::getline(rowStream, rowStr, ';')) {
                std::istringstream colStream(rowStr);
                std::string cellStr;
                int col = 0;
                while (std::getline(colStream, cellStr, ',')) {
                    if (!cellStr.empty()) {
                        // Trim whitespace
                        size_t start = cellStr.find_first_not_of(" \t");
                        if (start != std::string::npos) {
                            try {
                                int nodeNum = std::stoi(cellStr.substr(start));
                                if (nodeNum > 0) {
                                    cells.push_back({col, row, nodeNum});
                                }
                            } catch (...) {}
                        }
                    }
                    col++;
                    gridWidth = std::max(gridWidth, col);
                }
                row++;
            }
            gridHeight = row;
        }

        if (!cells.empty() && gridWidth > 0 && gridHeight > 0) {
            std::sort(cells.begin(), cells.end(),
                [](const CellInfo& a, const CellInfo& b) { return a.nodeNum < b.nodeNum; });

            float halfW = (float)(gridWidth - 1) / 2.0f;
            float halfH = (float)(gridHeight - 1) / 2.0f;

            nodes.reserve(cells.size());
            for (const auto& cell : cells) {
                NodeCoord nc;
                nc.x = wx + ((float)cell.col - halfW) * scaleX;
                nc.y = wy + ((float)(gridHeight - 1 - cell.row) - halfH) * scaleY;
                nc.z = wz;
                nc.bufX = cell.col;
                nc.bufY = gridHeight - 1 - cell.row;
                nodes.push_back(nc);
            }
        } else {
            NodeCoord nc;
            nc.x = wx; nc.y = wy; nc.z = wz;
            nodes.push_back(nc);
        }
    }
    else if (type == "Circle" || type == "Wreath") {
        // Circular arrangement of nodes in concentric rings.
        // LayerSizes attribute (e.g. "50,50,50") overrides parm1 for ring count
        // and defines the number of nodes per ring.
        float scaleX = attrFloat(attrs, "ScaleX", 1.0f);
        float scaleY = attrFloat(attrs, "ScaleY", 1.0f);
        if (std::abs(scaleX) < 0.001f) scaleX = 1.0f;
        if (std::abs(scaleY) < 0.001f) scaleY = 1.0f;

        // Parse LayerSizes if present (defines nodes per concentric ring)
        std::string layerSizesStr = attrStr(attrs, "LayerSizes");
        std::vector<int> layerSizes;
        if (!layerSizesStr.empty()) {
            std::istringstream lss(layerSizesStr);
            std::string token;
            while (std::getline(lss, token, ',')) {
                try {
                    int sz = std::stoi(token);
                    if (sz > 0) layerSizes.push_back(sz);
                } catch (...) {}
            }
        }

        int totalNodes;
        int circleParm3 = attrInt(attrs, "parm3", 0);
        float centerPct = (float)circleParm3 / 100.0f;

        if (!layerSizes.empty()) {
            // LayerSizes defines rings: outer ring first, inner ring last
            // Radius based on max nodes in any single layer (matches legacy CircleModel)
            int maxLayerSize = *std::max_element(layerSizes.begin(), layerSizes.end());
            totalNodes = 0;
            for (int sz : layerSizes) totalNodes += sz;

            float maxRadius = (float)maxLayerSize / 2.0f;
            if (maxRadius < 1.0f) maxRadius = 10.0f;
            float minRadius = centerPct * maxRadius;

            int numRings = (int)layerSizes.size();

            nodes.reserve(totalNodes);
            for (int ring = 0; ring < numRings; ring++) {
                // Interpolate radius from maxRadius (outer) to minRadius (inner)
                float t = (numRings > 1) ? (float)ring / (float)(numRings - 1) : 0.0f;
                float r = maxRadius - t * (maxRadius - minRadius);
                int nodesInRing = layerSizes[ring];
                for (int n = 0; n < nodesInRing; n++) {
                    float angle = 2.0f * 3.14159265f * (float)n / (float)nodesInRing;
                    NodeCoord nc;
                    nc.x = wx + r * std::cos(angle) * scaleX;
                    nc.y = wy + r * std::sin(angle) * scaleY;
                    nc.z = wz;
                    nc.bufX = n;
                    nc.bufY = ring;
                    nodes.push_back(nc);
                }
            }
        } else {
            // No LayerSizes: use parm1 for rings, parm2 for nodes per ring
            int numRings = parm1;
            int nodesPerRing = parm2;
            if (numRings < 1) numRings = 1;
            if (nodesPerRing < 1) nodesPerRing = 1;

            totalNodes = numRings * nodesPerRing;
            float maxRadius = (float)nodesPerRing / 2.0f;
            if (maxRadius < 1.0f) maxRadius = 10.0f;
            float minRadius = centerPct * maxRadius;

            nodes.reserve(totalNodes);
            for (int ring = 0; ring < numRings; ring++) {
                float t = (numRings > 1) ? (float)ring / (float)(numRings - 1) : 0.0f;
                float r = maxRadius - t * (maxRadius - minRadius);
                for (int n = 0; n < nodesPerRing; n++) {
                    float angle = 2.0f * 3.14159265f * (float)n / (float)nodesPerRing;
                    NodeCoord nc;
                    nc.x = wx + r * std::cos(angle) * scaleX;
                    nc.y = wy + r * std::sin(angle) * scaleY;
                    nc.z = wz;
                    nc.bufX = n;
                    nc.bufY = ring;
                    nodes.push_back(nc);
                }
            }
        }
    }
    else if (type == "Star") {
        // Star: concentric star layers, nodes along each layer's perimeter
        // parm1 = number of strings (concentric layers)
        // parm2 = nodes per string (nodes per layer)
        // parm3 = number of star points
        // LayerSizes overrides parm1 for layer count and defines nodes per layer
        float scaleX = attrFloat(attrs, "ScaleX", 1.0f);
        float scaleY = attrFloat(attrs, "ScaleY", 1.0f);
        if (std::abs(scaleX) < 0.001f) scaleX = 1.0f;
        if (std::abs(scaleY) < 0.001f) scaleY = 1.0f;

        int starPoints = attrInt(attrs, "parm3", 5);
        if (starPoints < 3) starPoints = 5;
        float starRatio = attrFloat(attrs, "starRatio", 2.618034f);
        if (starRatio < 1.01f) starRatio = 2.618034f;
        float innerPercent = attrFloat(attrs, "starCenterPercent", -1.0f);

        // Determine starting angle from StarStartLocation
        std::string startLoc = attrStr(attrs, "StarStartLocation", "Top Ctr-CCW");
        float startAngle = -3.14159265f / 2.0f; // Default: tip at top
        if (startLoc.find("Bottom") != std::string::npos) {
            startAngle = 3.14159265f / 2.0f; // Tip at bottom
        } else if (startLoc.find("Left") != std::string::npos) {
            startAngle = 3.14159265f;
        } else if (startLoc.find("Right") != std::string::npos) {
            startAngle = 0.0f;
        }

        // Parse LayerSizes if present (defines nodes per concentric star layer)
        std::string layerSizesStr = attrStr(attrs, "LayerSizes");
        std::vector<int> layerSizes;
        if (!layerSizesStr.empty()) {
            std::istringstream lss(layerSizesStr);
            std::string token;
            while (std::getline(lss, token, ',')) {
                try {
                    int sz = std::stoi(token);
                    if (sz > 0) layerSizes.push_back(sz);
                } catch (...) {}
            }
        }

        int numLayers;
        int totalNodes;
        if (!layerSizes.empty()) {
            numLayers = (int)layerSizes.size();
            totalNodes = 0;
            for (int sz : layerSizes) totalNodes += sz;
        } else {
            numLayers = parm1;
            if (numLayers < 1) numLayers = 1;
            int nodesPerLayer = parm2;
            if (nodesPerLayer < 1) nodesPerLayer = 1;
            totalNodes = numLayers * nodesPerLayer;
            for (int i = 0; i < numLayers; i++) layerSizes.push_back(nodesPerLayer);
        }

        // Buffer size uses legacy inflation formula: outer layers get inflated
        int maxLightsOnLayer = 0;
        for (int l = 0; l < numLayers; l++) {
            int layersOutside = numLayers - l - 1;
            int inflated = 1 + (int)((float)layerSizes[l] *
                (1.0f + ((float)layersOutside / (float)numLayers)));
            if (inflated > maxLightsOnLayer) maxLightsOnLayer = inflated;
        }

        float outerR = (float)maxLightsOnLayer / 2.0f;
        if (outerR < 1.0f) outerR = 10.0f;

        // Layer radius delta from innerPercent (default: 100/layerCount)
        if (innerPercent < 0) innerPercent = 100.0f / (float)numLayers;
        float layerRadiusDelta = 0;
        if (numLayers > 1) {
            layerRadiusDelta = (outerR * (100.0f - innerPercent))
                / (100.0f * ((float)numLayers - 1.0f));
        }

        nodes.reserve(totalNodes);

        for (int layer = 0; layer < numLayers; layer++) {
            float layerOuterR = outerR - layer * layerRadiusDelta;
            float layerInnerR = layerOuterR / starRatio;
            int nodesInLayer = layerSizes[layer];

            // Build star outline for this layer
            int numVerts = starPoints * 2;
            std::vector<float> vx(numVerts), vy(numVerts);
            for (int p = 0; p < starPoints; p++) {
                float oAngle = startAngle + 2.0f * 3.14159265f * (float)p / (float)starPoints;
                float iAngle = oAngle + 3.14159265f / (float)starPoints;
                vx[p * 2]     = layerOuterR * std::cos(oAngle);
                vy[p * 2]     = layerOuterR * std::sin(oAngle);
                vx[p * 2 + 1] = layerInnerR * std::cos(iAngle);
                vy[p * 2 + 1] = layerInnerR * std::sin(iAngle);
            }

            // Compute perimeter segment lengths
            std::vector<float> segLens(numVerts);
            float totalLen = 0;
            for (int i = 0; i < numVerts; i++) {
                int next = (i + 1) % numVerts;
                float dx = vx[next] - vx[i];
                float dy = vy[next] - vy[i];
                segLens[i] = std::sqrt(dx * dx + dy * dy);
                totalLen += segLens[i];
            }

            // Distribute nodes along this layer's star perimeter
            for (int n = 0; n < nodesInLayer; n++) {
                float dist = totalLen * (float)n / (float)nodesInLayer;
                float accumulated = 0;
                for (int s = 0; s < numVerts; s++) {
                    if (accumulated + segLens[s] >= dist || s == numVerts - 1) {
                        float t = (segLens[s] > 0.001f) ? (dist - accumulated) / segLens[s] : 0;
                        int next = (s + 1) % numVerts;
                        NodeCoord nc;
                        nc.x = wx + (vx[s] + (vx[next] - vx[s]) * t) * scaleX;
                        nc.y = wy + (vy[s] + (vy[next] - vy[s]) * t) * scaleY;
                        nc.z = wz;
                        nc.bufX = n;
                        nc.bufY = layer;
                        nodes.push_back(nc);
                        break;
                    }
                    accumulated += segLens[s];
                }
            }
        }
    }
    else if (type == "Poly Line" || type == "PolyLine") {
        // PolyLine: nodes distributed along a multi-segment path
        // PointData stores ALL waypoints as local coords: x0,y0,z0,x1,y1,z1,...
        // World position = local * scale + WorldPos
        float scaleX = attrFloat(attrs, "ScaleX", 1.0f);
        float scaleY = attrFloat(attrs, "ScaleY", 1.0f);
        float scaleZ = attrFloat(attrs, "ScaleZ", 1.0f);
        if (std::abs(scaleX) < 0.001f) scaleX = 1.0f;
        if (std::abs(scaleY) < 0.001f) scaleY = 1.0f;

        int numPoints = attrInt(attrs, "NumPoints", 2);
        std::string pointData = attrStr(attrs, "PointData");

        // Parse waypoints from PointData
        struct WP { float x, y, z; };
        std::vector<WP> waypoints;

        if (!pointData.empty()) {
            std::istringstream stream(pointData);
            std::string val;
            std::vector<float> coords;
            while (std::getline(stream, val, ',')) {
                try { coords.push_back(std::stof(val)); }
                catch (...) { coords.push_back(0.0f); }
            }
            for (size_t i = 0; i + 2 < coords.size(); i += 3) {
                WP wp;
                wp.x = wx + coords[i] * scaleX;
                wp.y = wy + coords[i + 1] * scaleY;
                wp.z = wz + coords[i + 2] * scaleZ;
                waypoints.push_back(wp);
            }
        }

        if (waypoints.size() < 2) {
            // Fallback to WorldPos → WorldPos+(X2,Y2)
            waypoints.clear();
            waypoints.push_back({wx, wy, wz});
            waypoints.push_back({wx + x2, wy + y2, wz + z2});
        }

        // Calculate total path length
        float totalLen = 0;
        std::vector<float> segLens;
        for (size_t i = 0; i + 1 < waypoints.size(); i++) {
            float dx = waypoints[i + 1].x - waypoints[i].x;
            float dy = waypoints[i + 1].y - waypoints[i].y;
            float dz = waypoints[i + 1].z - waypoints[i].z;
            float len = std::sqrt(dx * dx + dy * dy + dz * dz);
            segLens.push_back(len);
            totalLen += len;
        }

        int totalNodes = parm1 * parm2;
        if (totalNodes < 1) totalNodes = numPoints;
        if (totalNodes > 5000) totalNodes = 5000;

        // Distribute nodes evenly along the path
        nodes.reserve(totalNodes);
        for (int i = 0; i < totalNodes; i++) {
            float dist = (totalNodes > 1) ? totalLen * (float)i / (float)(totalNodes - 1) : 0;
            float accumulated = 0;
            for (size_t s = 0; s < segLens.size(); s++) {
                if (accumulated + segLens[s] >= dist || s == segLens.size() - 1) {
                    float t = (segLens[s] > 0.001f) ? (dist - accumulated) / segLens[s] : 0;
                    if (t > 1.0f) t = 1.0f;
                    NodeCoord nc;
                    nc.x = waypoints[s].x + (waypoints[s + 1].x - waypoints[s].x) * t;
                    nc.y = waypoints[s].y + (waypoints[s + 1].y - waypoints[s].y) * t;
                    nc.z = waypoints[s].z + (waypoints[s + 1].z - waypoints[s].z) * t;
                    nc.bufX = i;
                    nc.bufY = 0;
                    nodes.push_back(nc);
                    break;
                }
                accumulated += segLens[s];
            }
        }
    }
    else if (type.substr(0, 4) == "Tree") {
        // Tree models: "Tree 360", "Tree 180", "Tree Flat", "Tree Ribbon", etc.
        // parm1 = strings, parm2 = nodes per string, parm3 = strands per string
        float scaleX = attrFloat(attrs, "ScaleX", 1.0f);
        float scaleY = attrFloat(attrs, "ScaleY", 1.0f);
        if (std::abs(scaleX) < 0.001f) scaleX = 1.0f;
        if (std::abs(scaleY) < 0.001f) scaleY = 1.0f;

        int parm3 = attrInt(attrs, "parm3", 1);
        if (parm3 < 1) parm3 = 1;

        int numStrands = parm1 * parm3;          // total vertical strands
        int pixelsPerStrand = parm2 / parm3;     // nodes along each strand
        if (numStrands < 1) numStrands = 1;
        if (pixelsPerStrand < 1) pixelsPerStrand = 1;

        // Parse degrees from type name
        int degrees = 360;
        if (type == "Tree Flat") degrees = 0;
        else if (type == "Tree Ribbon") degrees = -1;
        else {
            size_t space = type.find(' ');
            if (space != std::string::npos) {
                try { degrees = std::stoi(type.substr(space + 1)); }
                catch (...) { degrees = 360; }
            }
        }

        // Legacy tree sizing: RenderHt = pixelsPerStrand * 3, RenderWi = RenderHt / 1.8
        float renderHt = (float)pixelsPerStrand * 3.0f;
        float renderWi = renderHt / 1.8f;
        float baseRadius = renderWi / 2.0f;

        // Top radius from TreeBottomTopRatio (default 6.0)
        float botTopRatio = attrFloat(attrs, "TreeBottomTopRatio", 6.0f);
        float topRadius = (std::abs(botTopRatio) > 0.01f)
            ? baseRadius / std::abs(botTopRatio)
            : 0.0f;
        if (botTopRatio < 0.0f) std::swap(baseRadius, topRadius);

        nodes.reserve(numStrands * pixelsPerStrand);

        if (degrees > 0) {
            // 3D cone: strands wrap around at the given degree arc
            float degreesRad = (float)degrees * 3.14159265f / 180.0f;
            for (int s = 0; s < numStrands; s++) {
                float angle = degreesRad * ((float)s / (float)std::max(numStrands - 1, 1) - 0.5f);
                for (int n = 0; n < pixelsPerStrand; n++) {
                    float posOnString = (pixelsPerStrand > 1)
                        ? (float)n / (float)(pixelsPerStrand - 1) : 0.5f;
                    float xb = baseRadius * std::sin(angle);
                    float xt = topRadius * std::sin(angle);
                    float zb = baseRadius * std::cos(angle);
                    float zt = topRadius * std::cos(angle);
                    NodeCoord nc;
                    nc.x = wx + (xb + (xt - xb) * posOnString) * scaleX;
                    nc.y = wy + (renderHt * posOnString - renderHt / 2.0f) * scaleY;
                    nc.z = wz + (zb + (zt - zb) * posOnString);
                    nc.bufX = s;
                    nc.bufY = n;
                    nodes.push_back(nc);
                }
            }
        } else {
            // Flat tree: trapezoidal shape (wider at bottom, narrower at top)
            float flatScale = 4.0f;
            for (int s = 0; s < numStrands; s++) {
                float xFrac = (float)s / (float)std::max(numStrands - 1, 1) - 0.5f;
                for (int n = 0; n < pixelsPerStrand; n++) {
                    float posOnString = (pixelsPerStrand > 1)
                        ? (float)n / (float)(pixelsPerStrand - 1) : 0.5f;
                    float xt = xFrac * 0.9f * (float)numStrands;
                    float xb = xFrac * flatScale * (float)numStrands;
                    NodeCoord nc;
                    nc.x = wx + (xb + (xt - xb) * posOnString) * scaleX;
                    nc.y = wy + (renderHt * posOnString - renderHt / 2.0f) * scaleY;
                    nc.z = wz;
                    nc.bufX = s;
                    nc.bufY = n;
                    nodes.push_back(nc);
                }
            }
        }
    }
    else if (type == "Window Frame") {
        // Nodes arranged along the edges of a rectangle
        float scaleX = attrFloat(attrs, "ScaleX", 1.0f);
        float scaleY = attrFloat(attrs, "ScaleY", 1.0f);
        if (std::abs(scaleX) < 0.001f) scaleX = 1.0f;
        if (std::abs(scaleY) < 0.001f) scaleY = 1.0f;

        int totalNodes = parm1 * parm2;
        if (totalNodes < 4) totalNodes = 4;
        if (totalNodes > 5000) totalNodes = 5000;

        float halfW = (float)(parm2 - 1) / 2.0f;
        float halfH = (float)(parm1 - 1) / 2.0f;
        if (halfW < 1.0f) halfW = 5.0f;
        if (halfH < 1.0f) halfH = 5.0f;

        // Distribute nodes around the rectangle perimeter
        float perimeter = 2.0f * (halfW * 2.0f + halfH * 2.0f);
        nodes.reserve(totalNodes);
        for (int i = 0; i < totalNodes; i++) {
            float dist = perimeter * (float)i / (float)totalNodes;
            float lx, ly;
            float w2 = halfW * 2.0f;
            float h2 = halfH * 2.0f;
            if (dist < w2) {
                lx = -halfW + dist; ly = -halfH; // bottom
            } else if (dist < w2 + h2) {
                lx = halfW; ly = -halfH + (dist - w2); // right
            } else if (dist < 2 * w2 + h2) {
                lx = halfW - (dist - w2 - h2); ly = halfH; // top
            } else {
                lx = -halfW; ly = halfH - (dist - 2 * w2 - h2); // left
            }

            NodeCoord nc;
            nc.x = wx + lx * scaleX;
            nc.y = wy + ly * scaleY;
            nc.z = wz;
            nc.bufX = i;
            nc.bufY = 0;
            nodes.push_back(nc);
        }
    }
    else {
        // Generic fallback handling two cases:
        // 1. BoxedScreenLocation models (Tree, Cube, Image,
        //    Spinner, Sphere, etc.): use ScaleX/ScaleY as per-node
        //    spacing centered at WorldPos.
        // 2. TwoPointScreenLocation fallback: distribute along X2/Y2 line.
        //
        // parm3 is included for models like Spinner where it represents
        // arc/layer count (total nodes = parm1 * parm2 * parm3).
        float scaleX = attrFloat(attrs, "ScaleX", 0.0f);
        float scaleY = attrFloat(attrs, "ScaleY", 0.0f);

        bool hasScale = (std::abs(scaleX) > 0.01f || std::abs(scaleY) > 0.01f);
        bool hasExtent = (std::abs(x2) > 0.1f || std::abs(y2) > 0.1f);

        if (hasScale) {
            // BoxedScreenLocation: grid of nodes centered at WorldPos
            // Include parm3 in total node count for multi-layer models (Spinner, etc.)
            int cols = (parm2 > 0) ? parm2 : 1;
            int rows = (parm1 > 0) ? parm1 * parm3 : 1;
            int totalNodes = cols * rows;
            if (totalNodes > 10000) {
                // Cap to prevent excessive vertex count
                float ratio = std::sqrt(10000.0f / totalNodes);
                cols = std::max(1, (int)(cols * ratio));
                rows = std::max(1, (int)(rows * ratio));
            }

            nodes.reserve(cols * rows);
            for (int r = 0; r < rows; r++) {
                for (int c = 0; c < cols; c++) {
                    NodeCoord nc;
                    nc.x = wx + ((float)c - (float)(cols - 1) / 2.0f) * scaleX;
                    nc.y = wy + ((float)r - (float)(rows - 1) / 2.0f) * scaleY;
                    nc.z = wz;
                    nc.bufX = c;
                    nc.bufY = r;
                    nodes.push_back(nc);
                }
            }
        } else if (hasExtent) {
            // TwoPointScreenLocation: distribute along X2/Y2 line
            int totalNodes = parm1 * parm2 * parm3;
            if (totalNodes < 1) totalNodes = 1;
            if (totalNodes > 10000) totalNodes = 10000;

            nodes.reserve(totalNodes);
            for (int i = 0; i < totalNodes; i++) {
                float t = (totalNodes > 1) ? (float)i / (float)(totalNodes - 1) : 0.5f;
                NodeCoord nc;
                nc.x = wx + x2 * t;
                nc.y = wy + y2 * t;
                nc.z = wz + z2 * t;
                nc.bufX = i % parm2;
                nc.bufY = i / parm2;
                nodes.push_back(nc);
            }
        } else {
            // No scale or extent info — generate all nodes sequentially
            // This ensures FSEQ channel data for all nodes is captured
            int totalNodes = parm1 * parm2 * parm3;
            if (totalNodes < 1) totalNodes = 1;
            if (totalNodes > 10000) totalNodes = 10000;

            int cols = (parm2 > 0) ? parm2 : 1;
            nodes.reserve(totalNodes);
            for (int i = 0; i < totalNodes; i++) {
                NodeCoord nc;
                nc.x = wx;
                nc.y = wy;
                nc.z = wz;
                nc.bufX = i % cols;
                nc.bufY = i / cols;
                nodes.push_back(nc);
            }
        }
    }

    return nodes;
}

ModelEngine::ModelEngine(IModelProvider* provider)
    : _provider(provider)
{
}

ModelEngine::~ModelEngine()
{
}

std::vector<std::string> ModelEngine::getModelNames() const
{
    if (!_provider) return {};
    return _provider->getModelNames();
}

std::vector<std::string> ModelEngine::getModelNamesExcludingGroups() const
{
    if (!_provider) return {};
    std::vector<std::string> result;
    for (const auto& name : _provider->getModelNames()) {
        auto attrs = _provider->getModelAttributes(name);
        auto it = attrs.find("DisplayAs");
        if (it == attrs.end() || it->second != "ModelGroup") {
            result.push_back(name);
        }
    }
    return result;
}

std::vector<std::string> ModelEngine::getGroupNames() const
{
    if (!_provider) return {};
    return _provider->getGroupNames();
}

bool ModelEngine::hasModel(const std::string& name) const
{
    if (!_provider) return false;
    return _provider->hasModel(name);
}

ModelInfo ModelEngine::getModel(const std::string& name) const
{
    if (!_provider || !_provider->hasModel(name)) return ModelInfo();

    auto attrs = _provider->getModelAttributes(name);
    if (attrs.empty()) return ModelInfo();

    ModelInfo info;
    info.name = name;
    auto typeIt = attrs.find("DisplayAs");
    info.type = (typeIt != attrs.end()) ? typeIt->second : "Unknown";
    info.isGroupModel = (info.type == "ModelGroup");
    info.layoutGroup = attrStr(attrs, "LayoutGroup", "Unassigned");
    info.startChannel = attrStr(attrs, "StartChannel", "1");
    info.controllerName = attrStr(attrs, "Controller");
    info.controllerProtocol = attrStr(attrs, "ControllerConnection.Protocol");
    info.controllerPort = attrInt(attrs, "ControllerConnection.Port", 0);
    info.isActive = (attrStr(attrs, "Active", "1") != "0");

    // Compute node count from generated nodes (handles all model types)
    auto nodes = generateNodesFromAttributes(attrs);
    info.nodeCount = (uint32_t)nodes.size();

    // Compute channels per node from StringType
    std::string stringType = attrStr(attrs, "StringType", "RGB Nodes");
    uint32_t chansPerNode = channelsPerNodeFromStringType(stringType);
    info.channelCount = info.nodeCount * chansPerNode;

    // Compute first/last channel from StartChannel attribute
    int32_t startCh = parseStartChannelSimple(info.startChannel);
    if (startCh >= 0) {
        info.firstChannel = (uint32_t)startCh;
        info.lastChannel = (info.channelCount > 0)
            ? info.firstChannel + info.channelCount - 1
            : info.firstChannel;
    }

    // Compute default buffer dimensions
    int p1 = attrInt(attrs, "parm1", 1);
    int p2 = attrInt(attrs, "parm2", 1);
    if (info.type == "Vert Matrix" || info.type == "Horiz Matrix" || info.type == "Matrix") {
        int p3 = attrInt(attrs, "parm3", 1);
        if (p3 < 1) p3 = 1;
        int numStrands = p1 * p3;
        int pixelsPerStrand = (p3 > 0) ? p2 / p3 : p2;
        if (info.type == "Vert Matrix") {
            info.defaultBufferWi = numStrands;
            info.defaultBufferHt = pixelsPerStrand;
        } else {
            info.defaultBufferWi = pixelsPerStrand;
            info.defaultBufferHt = numStrands;
        }
    } else {
        info.defaultBufferWi = (p2 > 0) ? p2 : 1;
        info.defaultBufferHt = (p1 > 0) ? p1 : 1;
    }

    info.properties = attrs;
    return info;
}

std::map<std::string, std::string> ModelEngine::getModelProperties(const std::string& name) const
{
    if (!_provider) return {};
    return _provider->getModelAttributes(name);
}

std::string ModelEngine::getModelProperty(const std::string& name, const std::string& key, const std::string& defaultValue) const
{
    if (!_provider) return defaultValue;
    auto attrs = _provider->getModelAttributes(name);
    auto it = attrs.find(key);
    return (it != attrs.end()) ? it->second : defaultValue;
}

std::vector<NodeCoord> ModelEngine::getModelNodes(const std::string& name) const
{
    if (!_provider) return {};
    auto attrs = _provider->getModelAttributes(name);
    if (attrs.empty()) return {};
    return generateNodesFromAttributes(attrs);
}

uint32_t ModelEngine::getModelNodeCount(const std::string& name) const
{
    if (!_provider || !_provider->hasModel(name)) return 0;
    auto attrs = _provider->getModelAttributes(name);
    if (attrs.empty()) return 0;
    auto nodes = generateNodesFromAttributes(attrs);
    return (uint32_t)nodes.size();
}

uint32_t ModelEngine::getModelChannelCount(const std::string& name) const
{
    if (!_provider || !_provider->hasModel(name)) return 0;
    auto attrs = _provider->getModelAttributes(name);
    if (attrs.empty()) return 0;
    auto nodes = generateNodesFromAttributes(attrs);
    std::string stringType = attrStr(attrs, "StringType", "RGB Nodes");
    return (uint32_t)nodes.size() * channelsPerNodeFromStringType(stringType);
}

OperationResult ModelEngine::createModel(const std::string& type, const std::string& name,
                                         const std::map<std::string, std::string>& properties)
{
    return {false, "Native build: model creation not yet implemented"};
}

OperationResult ModelEngine::deleteModel(const std::string& name)
{
    return {false, "Native build: model deletion not yet implemented"};
}

OperationResult ModelEngine::renameModel(const std::string& oldName, const std::string& newName)
{
    return {false, "Native build: model rename not yet implemented"};
}

OperationResult ModelEngine::updateModelProperty(const std::string& name, const std::string& key, const std::string& value)
{
    if (!_provider) return {false, "No provider available"};
    if (!_provider->hasModel(name)) return {false, "Model '" + name + "' not found"};

    auto* nativeProvider = dynamic_cast<NativeModelProvider*>(_provider);
    if (!nativeProvider) return {false, "Provider does not support property updates"};

    bool ok = nativeProvider->setModelAttribute(name, key, value);
    if (!ok) return {false, "Failed to set attribute '" + key + "' on model '" + name + "'"};

    // Notify listeners
    ModelChangeEvent event;
    event.type = ModelChangeType::PropertyChanged;
    event.modelName = name;
    event.propertyKey = key;
    event.propertyValue = value;
    notifyModelChanged(event);

    return {true, ""};
}

// --- Smart Remote (Native Build) ---

int ModelEngine::getSmartRemote(const std::string& name) const
{
    if (!_provider) return 0;
    auto attrs = _provider->getModelAttributes(name);
    auto it = attrs.find("ControllerConnection.SmartRemote");
    if (it != attrs.end()) {
        try { return std::stoi(it->second); } catch (...) {}
    }
    return 0;
}

std::string ModelEngine::getSmartRemoteType(const std::string& name) const
{
    if (!_provider) return "";
    auto attrs = _provider->getModelAttributes(name);
    auto it = attrs.find("ControllerConnection.SmartRemoteType");
    if (it != attrs.end()) {
        return it->second;
    }
    return "";
}

OperationResult ModelEngine::setSmartRemote(const std::string& name, int smartRemote)
{
    return {false, "Native build: smart remote update not yet implemented"};
}

OperationResult ModelEngine::setSmartRemoteType(const std::string& name, const std::string& type)
{
    return {false, "Native build: smart remote type update not yet implemented"};
}

std::vector<SubmodelInfo> ModelEngine::getSubmodels(const std::string& modelName) const
{
    if (!_provider) return {};
    std::vector<SubmodelInfo> result;
    auto names = _provider->getSubmodels(modelName);
    result.reserve(names.size());
    for (const auto& smName : names) {
        SubmodelInfo info;
        info.name = smName;
        info.fullName = modelName + "/" + smName;
        result.push_back(info);
    }
    return result;
}

bool ModelEngine::hasSubmodel(const std::string& modelName, const std::string& submodelName) const
{
    if (!_provider) return false;
    auto names = _provider->getSubmodels(modelName);
    return std::find(names.begin(), names.end(), submodelName) != names.end();
}

SubmodelDefinition ModelEngine::getSubmodelDefinition(const std::string& modelName, const std::string& submodelName) const
{
    SubmodelDefinition def;
    if (!_provider) return def;

    auto attrs = _provider->getSubmodelAttributes(modelName, submodelName);
    if (attrs.empty()) return def;

    def.name = submodelName;
    auto typeIt = attrs.find("type");
    def.isRanges = (typeIt == attrs.end() || typeIt->second == "ranges");
    auto layoutIt = attrs.find("layout");
    def.vertical = (layoutIt != attrs.end() && layoutIt->second == "vertical");
    auto bsIt = attrs.find("bufferstyle");
    def.bufferStyle = (bsIt != attrs.end()) ? bsIt->second : "Default";
    auto sbIt = attrs.find("subBuffer");
    def.subBuffer = (sbIt != attrs.end()) ? sbIt->second : "";

    if (def.isRanges) {
        for (int i = 0; ; i++) {
            std::string key = "line" + std::to_string(i);
            auto it = attrs.find(key);
            if (it == attrs.end()) break;
            def.strands.push_back(it->second);
        }
    }

    return def;
}

OperationResult ModelEngine::setSubmodel(const std::string& modelName, const std::string& submodelName,
                                         const SubmodelDefinition& definition)
{
    if (!_provider) return {false, "No provider available"};
    if (!_provider->hasModel(modelName)) return {false, "Model '" + modelName + "' not found"};

    std::map<std::string, std::string> attrs;
    attrs["name"] = submodelName;
    attrs["type"] = definition.isRanges ? "ranges" : "subbuffer";
    attrs["layout"] = definition.vertical ? "vertical" : "horizontal";
    attrs["bufferstyle"] = definition.bufferStyle.empty() ? "Default" : definition.bufferStyle;

    if (definition.isRanges) {
        for (size_t i = 0; i < definition.strands.size(); i++) {
            attrs["line" + std::to_string(i)] = definition.strands[i];
        }
    } else {
        attrs["subBuffer"] = definition.subBuffer;
    }

    bool ok = _provider->setSubmodelAttributes(modelName, submodelName, attrs);
    if (ok) {
        ModelChangeEvent event;
        event.type = ModelChangeType::Modified;
        event.modelName = modelName;
        const_cast<ModelEngine*>(this)->notifyModelChanged(event);
    }
    return {ok, ok ? "" : "Failed to set submodel"};
}

OperationResult ModelEngine::deleteSubmodel(const std::string& modelName, const std::string& submodelName)
{
    if (!_provider) return {false, "No provider available"};
    if (!_provider->hasModel(modelName)) return {false, "Model '" + modelName + "' not found"};

    bool ok = _provider->deleteSubmodel(modelName, submodelName);
    if (ok) {
        ModelChangeEvent event;
        event.type = ModelChangeType::Modified;
        event.modelName = modelName;
        const_cast<ModelEngine*>(this)->notifyModelChanged(event);
    }
    return {ok, ok ? "" : "Submodel '" + submodelName + "' not found"};
}

OperationResult ModelEngine::renameSubmodel(const std::string& modelName, const std::string& oldName,
                                            const std::string& newName)
{
    if (!_provider) return {false, "No provider available"};
    if (!_provider->hasModel(modelName)) return {false, "Model '" + modelName + "' not found"};

    bool ok = _provider->renameSubmodel(modelName, oldName, newName);
    if (ok) {
        ModelChangeEvent event;
        event.type = ModelChangeType::Modified;
        event.modelName = modelName;
        const_cast<ModelEngine*>(this)->notifyModelChanged(event);
    }
    return {ok, ok ? "" : "Failed to rename submodel"};
}

// Helper to parse comma-separated model list from group attributes
static std::vector<std::string> parseModelList(const std::string& modelsStr) {
    std::vector<std::string> result;
    std::istringstream stream(modelsStr);
    std::string token;
    while (std::getline(stream, token, ',')) {
        size_t start = token.find_first_not_of(" \t");
        size_t end = token.find_last_not_of(" \t");
        if (start != std::string::npos) {
            result.push_back(token.substr(start, end - start + 1));
        }
    }
    return result;
}

// Filter parent model nodes to only the subset referenced by a submodel's strand ranges.
// Returns filtered nodes with reassigned bufX/bufY for compact layout.
std::vector<xlEngine::NodeCoord> xlEngine::filterNodesToSubmodel(
    const std::vector<xlEngine::NodeCoord>& allParentNodes,
    const std::map<std::string, std::string>& subAttrs)
{
    auto typeIt = subAttrs.find("type");
    bool isRanges = true;
    if (typeIt != subAttrs.end() && typeIt->second == "subbuffer") {
        isRanges = false;
    }

    if (!isRanges) {
        return allParentNodes;
    }

    // Ranges type: parse line0, line1, ... to get node indices
    // Each lineN becomes a row; nodes within become columns
    std::vector<xlEngine::NodeCoord> result;
    for (int lineIdx = 0; lineIdx < 100; ++lineIdx) {
        std::string key = "line" + std::to_string(lineIdx);
        auto it = subAttrs.find(key);
        if (it == subAttrs.end() || it->second.empty()) {
            if (lineIdx > 0) break;
            continue;
        }
        // Parse comma-separated ranges
        std::istringstream stream(it->second);
        std::string token;
        int col = 0;
        while (std::getline(stream, token, ',')) {
            size_t start = token.find_first_not_of(" \t");
            size_t end = token.find_last_not_of(" \t");
            if (start == std::string::npos) continue;
            token = token.substr(start, end - start + 1);
            if (token.empty()) continue;

            size_t dash = token.find('-');
            int rangeStart, rangeEnd;
            if (dash != std::string::npos) {
                rangeStart = std::atoi(token.substr(0, dash).c_str()) - 1;
                rangeEnd = std::atoi(token.substr(dash + 1).c_str()) - 1;
                if (rangeStart < 0) rangeStart = 0;
                if (rangeEnd < rangeStart) std::swap(rangeStart, rangeEnd);
            } else {
                rangeStart = rangeEnd = std::atoi(token.c_str()) - 1;
                if (rangeStart < 0) continue;
            }

            for (int idx = rangeStart; idx <= rangeEnd; ++idx) {
                if (idx >= 0 && idx < (int)allParentNodes.size()) {
                    xlEngine::NodeCoord nc = allParentNodes[idx];
                    nc.bufX = col;
                    nc.bufY = lineIdx;
                    nc.parentNodeIndex = idx;
                    result.push_back(nc);
                    col++;
                }
            }
        }
    }
    return result;
}

// Helper to get NativeModelProvider from the provider pointer
static NativeModelProvider* getNativeProvider(IModelProvider* provider) {
    return dynamic_cast<NativeModelProvider*>(provider);
}

std::vector<ModelGroupInfo> ModelEngine::getModelGroups() const
{
    if (!_provider) return {};

    auto* nativeProvider = getNativeProvider(_provider);
    if (!nativeProvider) return {};

    std::vector<ModelGroupInfo> result;
    auto groupNames = _provider->getGroupNames();
    for (const auto& gName : groupNames) {
        auto attrs = nativeProvider->getGroupAttributes(gName);
        ModelGroupInfo info;
        info.name = gName;
        auto modelsIt = attrs.find("models");
        if (modelsIt != attrs.end()) {
            info.modelNames = parseModelList(modelsIt->second);
        }
        auto bsIt = attrs.find("layout");
        if (bsIt != attrs.end()) {
            info.defaultBufferStyle = bsIt->second;
        }
        result.push_back(info);
    }
    return result;
}

ModelGroupInfo ModelEngine::getModelGroup(const std::string& groupName) const
{
    ModelGroupInfo info;
    if (!_provider) return info;

    auto* nativeProvider = getNativeProvider(_provider);
    if (!nativeProvider) return info;

    auto attrs = nativeProvider->getGroupAttributes(groupName);
    if (attrs.empty()) return info;

    info.name = groupName;
    auto modelsIt = attrs.find("models");
    if (modelsIt != attrs.end()) {
        info.modelNames = parseModelList(modelsIt->second);
    }
    auto bsIt = attrs.find("layout");
    if (bsIt != attrs.end()) {
        info.defaultBufferStyle = bsIt->second;
    }
    return info;
}

std::vector<std::string> ModelEngine::getGroupsContainingModel(const std::string& modelName) const
{
    if (!_provider) return {};

    auto* nativeProvider = getNativeProvider(_provider);
    if (!nativeProvider) return {};

    std::vector<std::string> result;
    auto groupNames = _provider->getGroupNames();
    for (const auto& gName : groupNames) {
        auto attrs = nativeProvider->getGroupAttributes(gName);
        auto modelsIt = attrs.find("models");
        if (modelsIt != attrs.end()) {
            auto members = parseModelList(modelsIt->second);
            if (std::find(members.begin(), members.end(), modelName) != members.end()) {
                result.push_back(gName);
            }
        }
    }
    return result;
}

OperationResult ModelEngine::createModelGroup(const std::string& groupName,
                                              const std::vector<std::string>& modelNames)
{
    if (!_provider) return {false, "No provider available"};

    auto* nativeProvider = getNativeProvider(_provider);
    if (!nativeProvider) return {false, "Write operations not supported by this provider"};

    std::string modelList;
    for (size_t i = 0; i < modelNames.size(); i++) {
        if (i > 0) modelList += ",";
        modelList += modelNames[i];
    }

    bool ok = nativeProvider->createGroup(groupName, modelList);
    if (ok) {
        ModelChangeEvent event;
        event.type = ModelChangeType::Added;
        event.modelName = groupName;
        const_cast<ModelEngine*>(this)->notifyModelChanged(event);
    }
    return {ok, ok ? "" : "Failed to create model group '" + groupName + "'"};
}

OperationResult ModelEngine::deleteModelGroup(const std::string& groupName)
{
    if (!_provider) return {false, "No provider available"};

    auto* nativeProvider = getNativeProvider(_provider);
    if (!nativeProvider) return {false, "Write operations not supported by this provider"};

    bool ok = nativeProvider->deleteGroup(groupName);
    if (ok) {
        ModelChangeEvent event;
        event.type = ModelChangeType::Removed;
        event.modelName = groupName;
        const_cast<ModelEngine*>(this)->notifyModelChanged(event);
    }
    return {ok, ok ? "" : "Group '" + groupName + "' not found"};
}

OperationResult ModelEngine::renameModelGroup(const std::string& oldName, const std::string& newName)
{
    if (!_provider) return {false, "No provider available"};

    auto* nativeProvider = getNativeProvider(_provider);
    if (!nativeProvider) return {false, "Write operations not supported by this provider"};

    bool ok = nativeProvider->renameGroup(oldName, newName);
    if (ok) {
        ModelChangeEvent event;
        event.type = ModelChangeType::Renamed;
        event.modelName = newName;
        event.oldName = oldName;
        const_cast<ModelEngine*>(this)->notifyModelChanged(event);
    }
    return {ok, ok ? "" : "Failed to rename group '" + oldName + "'"};
}

OperationResult ModelEngine::addModelToGroup(const std::string& groupName, const std::string& modelName)
{
    if (!_provider) return {false, "No provider available"};

    auto* nativeProvider = getNativeProvider(_provider);
    if (!nativeProvider) return {false, "Write operations not supported by this provider"};

    bool ok = nativeProvider->addModelToGroup(groupName, modelName);
    if (ok) {
        ModelChangeEvent event;
        event.type = ModelChangeType::Modified;
        event.modelName = groupName;
        const_cast<ModelEngine*>(this)->notifyModelChanged(event);
    }
    return {ok, ok ? "" : "Failed to add model to group"};
}

OperationResult ModelEngine::removeModelFromGroup(const std::string& groupName, const std::string& modelName)
{
    if (!_provider) return {false, "No provider available"};

    auto* nativeProvider = getNativeProvider(_provider);
    if (!nativeProvider) return {false, "Write operations not supported by this provider"};

    bool ok = nativeProvider->removeModelFromGroup(groupName, modelName);
    if (ok) {
        ModelChangeEvent event;
        event.type = ModelChangeType::Modified;
        event.modelName = groupName;
        const_cast<ModelEngine*>(this)->notifyModelChanged(event);
    }
    return {ok, ok ? "" : "Failed to remove model from group"};
}

ModelEngine::BoundingBox ModelEngine::getModelBounds(const std::string& name) const
{
    if (!_provider) return BoundingBox();

    auto attrs = _provider->getModelAttributes(name);
    if (attrs.empty()) return BoundingBox();

    // Compute bounding box from actual generated nodes
    auto nodes = generateNodesFromAttributes(attrs);
    if (nodes.empty()) return BoundingBox();

    BoundingBox bb;
    bb.minX = bb.maxX = nodes[0].x;
    bb.minY = bb.maxY = nodes[0].y;
    bb.minZ = bb.maxZ = nodes[0].z;
    for (size_t i = 1; i < nodes.size(); i++) {
        bb.minX = std::min(bb.minX, nodes[i].x);
        bb.maxX = std::max(bb.maxX, nodes[i].x);
        bb.minY = std::min(bb.minY, nodes[i].y);
        bb.maxY = std::max(bb.maxY, nodes[i].y);
        bb.minZ = std::min(bb.minZ, nodes[i].z);
        bb.maxZ = std::max(bb.maxZ, nodes[i].z);
    }

    // Add small padding so single-point models aren't zero-size
    float pad = 2.0f;
    bb.minX -= pad;  bb.maxX += pad;
    bb.minY -= pad;  bb.maxY += pad;
    bb.minZ -= pad;  bb.maxZ += pad;
    return bb;
}

// --- Group Buffer Nodes (native) ---

// Recursively resolve group members to leaf models, expanding nested groups
// and preserving submodel references (e.g. "Model/Submodel").
static void resolveGroupMembersRecursive(
    const std::vector<std::string>& members,
    NativeModelProvider* provider,
    std::vector<std::string>& outLeaves,
    std::set<std::string>& visited,
    int depth = 0)
{
    if (depth > 10) return;

    for (const auto& member : members) {
        if (visited.count(member)) continue;
        visited.insert(member);

        // Check if member is a group (has "models" in group attributes)
        auto groupAttrs = provider->getGroupAttributes(member);
        auto modelsIt = groupAttrs.find("models");
        if (modelsIt != groupAttrs.end() && !modelsIt->second.empty()) {
            auto subMembers = parseModelList(modelsIt->second);
            resolveGroupMembersRecursive(subMembers, provider, outLeaves, visited, depth + 1);
            continue;
        }

        // Leaf model or submodel reference
        outLeaves.push_back(member);
    }
}

std::vector<ModelEngine::GroupMemberNodes> ModelEngine::getGroupBufferNodes(
    const std::string& groupName) const
{
    std::vector<GroupMemberNodes> result;
    if (!_provider) return result;

    auto* nativeProvider = getNativeProvider(_provider);
    if (!nativeProvider) return result;

    auto groupAttrs = nativeProvider->getGroupAttributes(groupName);
    auto modelsIt = groupAttrs.find("models");
    if (modelsIt == groupAttrs.end() || modelsIt->second.empty()) return result;

    auto directMembers = parseModelList(modelsIt->second);
    if (directMembers.empty()) return result;

    // Recursively flatten to leaf models/submodel refs
    std::vector<std::string> leafMembers;
    std::set<std::string> visited;
    resolveGroupMembersRecursive(directMembers, nativeProvider, leafMembers, visited);
    if (leafMembers.empty()) return result;

    // Collect world-space nodes for all leaf members and compute global bounding box
    struct MemberData {
        std::string name;
        std::vector<NodeCoord> nodes;
    };
    std::vector<MemberData> allMembers;
    float globalMinX = 1e30f, globalMaxX = -1e30f;
    float globalMinY = 1e30f, globalMaxY = -1e30f;

    printf("[GRP] getGroupBufferNodes('%s'): %zu leaves\n", groupName.c_str(), leafMembers.size());

    for (const auto& memberName : leafMembers) {
        std::vector<NodeCoord> nodes;

        // Check for submodel reference ("ParentModel/SubmodelName")
        size_t slash = memberName.find('/');
        if (slash != std::string::npos) {
            std::string parentName = memberName.substr(0, slash);
            std::string subName = memberName.substr(slash + 1);
            auto parentAttrs = _provider->getModelAttributes(parentName);
            if (!parentAttrs.empty()) {
                auto allParentNodes = generateNodesFromAttributes(parentAttrs);
                auto subAttrs = _provider->getSubmodelAttributes(parentName, subName);
                if (!subAttrs.empty()) {
                    nodes = filterNodesToSubmodel(allParentNodes, subAttrs);
                    printf("[GRP]   '%s': %zu→%zu nodes (filtered)\n", memberName.c_str(), allParentNodes.size(), nodes.size());
                } else {
                    nodes = std::move(allParentNodes);
                    printf("[GRP]   '%s': %zu nodes (NO subAttrs!)\n", memberName.c_str(), nodes.size());
                }
            } else {
                printf("[GRP]   '%s': parent '%s' has no attrs!\n", memberName.c_str(), parentName.c_str());
            }
        } else {
            auto attrs = _provider->getModelAttributes(memberName);
            if (!attrs.empty()) {
                nodes = generateNodesFromAttributes(attrs);
                printf("[GRP]   '%s': %zu nodes\n", memberName.c_str(), nodes.size());
            } else {
                printf("[GRP]   '%s': NO attrs!\n", memberName.c_str());
            }
        }

        if (nodes.empty()) continue;

        for (const auto& n : nodes) {
            globalMinX = std::min(globalMinX, n.x);
            globalMaxX = std::max(globalMaxX, n.x);
            globalMinY = std::min(globalMinY, n.y);
            globalMaxY = std::max(globalMaxY, n.y);
        }
        allMembers.push_back({memberName, std::move(nodes)});
    }

    if (allMembers.empty()) return result;

    // Remap world coords to 2D buffer layout (minimalGrid style)
    float rangeX = globalMaxX - globalMinX;
    float rangeY = globalMaxY - globalMinY;
    if (rangeX < 1.0f) rangeX = 1.0f;
    if (rangeY < 1.0f) rangeY = 1.0f;

    int gridSize = 400;
    auto gsIt = groupAttrs.find("GridSize");
    if (gsIt != groupAttrs.end() && !gsIt->second.empty()) {
        try { gridSize = std::stoi(gsIt->second); } catch (...) {}
    }
    if (gridSize < 10) gridSize = 400;

    // Determine aspect-preserving grid dimensions
    float aspect = rangeX / rangeY;
    int gridW, gridH;
    if (aspect >= 1.0f) {
        gridW = gridSize;
        gridH = std::max(1, (int)(gridSize / aspect));
    } else {
        gridH = gridSize;
        gridW = std::max(1, (int)(gridSize * aspect));
    }

    result.reserve(allMembers.size());
    for (auto& md : allMembers) {
        GroupMemberNodes gmn;
        gmn.modelName = md.name;
        gmn.nodes.reserve(md.nodes.size());

        BoundingBox bb;
        bool first = true;

        for (auto& n : md.nodes) {
            // Normalize to [0,1] then scale to grid
            float nx = (n.x - globalMinX) / rangeX;
            float ny = (n.y - globalMinY) / rangeY;
            n.x = nx * gridW;
            n.y = ny * gridH;
            n.z = 0.0f;

            if (first) {
                bb.minX = bb.maxX = n.x;
                bb.minY = bb.maxY = n.y;
                bb.minZ = bb.maxZ = 0;
                first = false;
            } else {
                bb.minX = std::min(bb.minX, n.x);
                bb.maxX = std::max(bb.maxX, n.x);
                bb.minY = std::min(bb.minY, n.y);
                bb.maxY = std::max(bb.maxY, n.y);
            }

            gmn.nodes.push_back(n);
        }

        float pad = 2.0f;
        bb.minX -= pad; bb.maxX += pad;
        bb.minY -= pad; bb.maxY += pad;
        bb.minZ -= pad; bb.maxZ += pad;
        gmn.bounds = bb;

        result.push_back(std::move(gmn));
    }

    return result;
}

// --- Face Definitions (native) ---

std::vector<std::string> ModelEngine::getFaceNames(const std::string& modelName) const {
    auto* nmp = dynamic_cast<NativeModelProvider*>(_provider);
    if (nmp) return nmp->getFaceNames(modelName);
    return {};
}

std::map<std::string, std::string> ModelEngine::getFaceDefinition(
    const std::string& modelName, const std::string& faceName) const {
    auto* nmp = dynamic_cast<NativeModelProvider*>(_provider);
    if (nmp) return nmp->getFaceDefinition(modelName, faceName);
    return {};
}

std::map<std::string, std::map<std::string, std::string>> ModelEngine::getAllFaceDefinitions(
    const std::string& modelName) const {
    auto* nmp = dynamic_cast<NativeModelProvider*>(_provider);
    if (nmp) return nmp->getAllFaceDefinitions(modelName);
    return {};
}

OperationResult ModelEngine::setFaceDefinition(const std::string& modelName, const std::string& faceName,
                                               const std::map<std::string, std::string>& definition) {
    auto* nmp = dynamic_cast<NativeModelProvider*>(_provider);
    if (!nmp) return {false, "Provider does not support face definitions"};
    return {nmp->setFaceDefinition(modelName, faceName, definition), ""};
}

OperationResult ModelEngine::setAllFaceDefinitions(const std::string& modelName,
    const std::map<std::string, std::map<std::string, std::string>>& definitions) {
    auto* nmp = dynamic_cast<NativeModelProvider*>(_provider);
    if (!nmp) return {false, "Provider does not support face definitions"};
    return {nmp->setAllFaceDefinitions(modelName, definitions), ""};
}

OperationResult ModelEngine::deleteFaceDefinition(const std::string& modelName, const std::string& faceName) {
    auto* nmp = dynamic_cast<NativeModelProvider*>(_provider);
    if (!nmp) return {false, "Provider does not support face definitions"};
    return {nmp->deleteFaceDefinition(modelName, faceName), ""};
}

OperationResult ModelEngine::renameFaceDefinition(const std::string& modelName,
                                                  const std::string& oldName, const std::string& newName) {
    auto* nmp = dynamic_cast<NativeModelProvider*>(_provider);
    if (!nmp) return {false, "Provider does not support face definitions"};
    return {nmp->renameFaceDefinition(modelName, oldName, newName), ""};
}

// --- Dimming Curves (native build) ---

std::map<std::string, std::map<std::string, std::string>> ModelEngine::getDimmingInfo(
    const std::string& modelName) const {
    auto* nmp = dynamic_cast<NativeModelProvider*>(_provider);
    if (nmp) return nmp->getDimmingInfo(modelName);
    return {};
}

OperationResult ModelEngine::setDimmingInfo(const std::string& modelName,
    const std::map<std::string, std::map<std::string, std::string>>& dimmingInfo) {
    auto* nmp = dynamic_cast<NativeModelProvider*>(_provider);
    if (!nmp) return {false, "Provider does not support dimming curves"};
    bool ok = nmp->setDimmingInfo(modelName, dimmingInfo);
    if (ok) {
        ModelChangeEvent event;
        event.type = ModelChangeType::PropertyChanged;
        event.modelName = modelName;
        const_cast<ModelEngine*>(this)->notifyModelChanged(event);
    }
    return {ok, ok ? "" : "Failed to set dimming info"};
}

void ModelEngine::addListener(ModelEngineListener* listener)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    _listeners.push_back(listener);
}

void ModelEngine::removeListener(ModelEngineListener* listener)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    _listeners.erase(
        std::remove(_listeners.begin(), _listeners.end(), listener),
        _listeners.end());
}

void ModelEngine::notifyModelChanged(const ModelChangeEvent& event)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        switch (event.type) {
            case ModelChangeType::Added:
                listener->onModelAdded(event);
                break;
            case ModelChangeType::Removed:
                listener->onModelRemoved(event);
                break;
            case ModelChangeType::Modified:
                listener->onModelModified(event);
                break;
            case ModelChangeType::Renamed:
                listener->onModelRenamed(event);
                break;
            case ModelChangeType::PropertyChanged:
                listener->onModelPropertyChanged(event);
                break;
        }
    }
}

#else
// Legacy build: full implementation using wxWidgets and Model classes

ModelEngine::ModelEngine(IModelProvider* provider)
    : _provider(provider)
    , _ownedAdapter(nullptr)
{
}

ModelEngine::ModelEngine(ModelManager& modelManager)
    : _ownedAdapter(std::make_unique<ModelManagerAdapter>(modelManager))
    , _provider(_ownedAdapter.get())
{
}

ModelEngine::~ModelEngine()
{
}

// --- Private Helpers ---

Model* ModelEngine::findModel(const std::string& name) const
{
    return _provider->getModel(name);
}

ModelManagerAdapter* ModelEngine::getAdapter() const
{
    // Try to get the adapter for write operations.
    // If _ownedAdapter is set, we created it ourselves.
    // Otherwise, try to dynamic_cast the provider.
    if (_ownedAdapter) {
        return _ownedAdapter.get();
    }
    return dynamic_cast<ModelManagerAdapter*>(_provider);
}

ModelInfo ModelEngine::buildModelInfo(const Model* model) const
{
    ModelInfo info;
    if (model == nullptr)
        return info;

    info.name = model->GetName();
    info.type = model->GetDisplayAs();
    info.description = model->description;
    info.nodeCount = model->GetNodeCount();
    info.channelCount = model->GetChanCount();
    info.firstChannel = model->GetFirstChannel();
    info.lastChannel = model->GetLastChannel();
    info.defaultBufferWi = model->GetDefaultBufferWi();
    info.defaultBufferHt = model->GetDefaultBufferHt();
    info.startChannel = model->ModelStartChannel;
    info.layoutGroup = model->GetLayoutGroup();
    info.controllerName = model->GetControllerName();
    info.controllerProtocol = model->GetControllerProtocol();
    info.controllerPort = model->GetControllerPort();
    info.smartRemote = model->GetSmartRemote();
    info.smartRemoteType = model->GetSmartRemoteType();
    info.isActive = model->IsActive();
    info.isGroupModel = (info.type == "ModelGroup");

    // Extract all XML attributes as string properties
    wxXmlNode* xml = model->GetModelXml();
    if (xml != nullptr) {
        for (wxXmlAttribute* attr = xml->GetAttributes(); attr != nullptr; attr = attr->GetNext()) {
            info.properties[attr->GetName().ToStdString()] = attr->GetValue().ToStdString();
        }
    }

    return info;
}

// --- Enumeration ---

std::vector<std::string> ModelEngine::getModelNames() const
{
    return _provider->getModelNames();
}

std::vector<std::string> ModelEngine::getModelNamesExcludingGroups() const
{
    std::vector<std::string> names;
    auto allNames = _provider->getModelNames();
    for (const auto& name : allNames) {
        const Model* m = _provider->getModel(name);
        if (m != nullptr && m->GetDisplayAs() != "ModelGroup") {
            names.push_back(name);
        }
    }
    return names;
}

std::vector<std::string> ModelEngine::getGroupNames() const
{
    return _provider->getGroupNames();
}

// --- Model Metadata ---

bool ModelEngine::hasModel(const std::string& name) const
{
    return findModel(name) != nullptr;
}

ModelInfo ModelEngine::getModel(const std::string& name) const
{
    Model* m = findModel(name);
    return buildModelInfo(m);
}

std::map<std::string, std::string> ModelEngine::getModelProperties(const std::string& name) const
{
    std::map<std::string, std::string> props;
    Model* m = findModel(name);
    if (m == nullptr)
        return props;

    wxXmlNode* xml = m->GetModelXml();
    if (xml == nullptr)
        return props;

    for (wxXmlAttribute* attr = xml->GetAttributes(); attr != nullptr; attr = attr->GetNext()) {
        props[attr->GetName().ToStdString()] = attr->GetValue().ToStdString();
    }

    // Also include controller connection attributes
    wxXmlNode* cc = m->GetControllerConnection();
    if (cc != nullptr) {
        for (wxXmlAttribute* attr = cc->GetAttributes(); attr != nullptr; attr = attr->GetNext()) {
            std::string key = "ControllerConnection." + attr->GetName().ToStdString();
            props[key] = attr->GetValue().ToStdString();
        }
    }

    return props;
}

std::string ModelEngine::getModelProperty(const std::string& name, const std::string& key, const std::string& defaultValue) const
{
    Model* m = findModel(name);
    if (m == nullptr)
        return defaultValue;

    wxXmlNode* xml = m->GetModelXml();
    if (xml == nullptr)
        return defaultValue;

    wxString val = xml->GetAttribute(key, defaultValue);
    return val.ToStdString();
}

// --- Node Data ---

std::vector<NodeCoord> ModelEngine::getModelNodes(const std::string& name) const
{
    std::vector<NodeCoord> result;
    Model* m = findModel(name);
    if (m == nullptr)
        return result;

    uint32_t nodeCount = m->GetNodeCount();
    result.reserve(nodeCount);

    for (uint32_t i = 0; i < nodeCount; ++i) {
        NodeBaseClass* node = m->GetNode(i);
        if (node == nullptr)
            continue;

        NodeCoord nc;
        nc.actChannel = node->ActChan;
        nc.channelCount = node->GetChanCount();
        nc.stringNum = node->StringNum;

        // Use the first coordinate of the node for position
        if (!node->Coords.empty()) {
            nc.bufX = node->Coords[0].bufX;
            nc.bufY = node->Coords[0].bufY;
            nc.x = node->Coords[0].screenX;
            nc.y = node->Coords[0].screenY;
            nc.z = node->Coords[0].screenZ;
        }

        result.push_back(nc);
    }

    return result;
}

uint32_t ModelEngine::getModelNodeCount(const std::string& name) const
{
    Model* m = findModel(name);
    if (m == nullptr)
        return 0;
    return m->GetNodeCount();
}

uint32_t ModelEngine::getModelChannelCount(const std::string& name) const
{
    Model* m = findModel(name);
    if (m == nullptr)
        return 0;
    return m->GetChanCount();
}

// --- Model CRUD ---

OperationResult ModelEngine::createModel(const std::string& type, const std::string& name,
                                         const std::map<std::string, std::string>& properties)
{
    if (_provider->hasModel(name))
        return {false, "Model '" + name + "' already exists"};

    ModelManagerAdapter* adapter = getAdapter();
    if (adapter == nullptr)
        return {false, "Write operations not supported by this provider"};

    std::string startChannel = "1";
    auto scIt = properties.find("StartChannel");
    if (scIt != properties.end()) {
        startChannel = scIt->second;
    }

    Model* model = adapter->createDefaultModel(type, startChannel);
    if (model == nullptr)
        return {false, "Failed to create model of type '" + type + "'"};

    wxXmlNode* xml = model->GetModelXml();
    if (xml != nullptr) {
        xml->DeleteAttribute("name");
        xml->AddAttribute("name", name);
    }
    model->name = name;

    for (const auto& [key, value] : properties) {
        if (key == "StartChannel")
            continue;
        if (xml != nullptr) {
            if (xml->HasAttribute(key)) {
                xml->DeleteAttribute(key);
            }
            xml->AddAttribute(key, value);
        }
    }

    model->SetFromXml(xml);
    adapter->addModel(model);

    ModelChangeEvent event;
    event.type = ModelChangeType::Added;
    event.modelName = name;
    notifyModelChanged(event);

    return {true, ""};
}

OperationResult ModelEngine::deleteModel(const std::string& name)
{
    if (!_provider->hasModel(name))
        return {false, "Model '" + name + "' not found"};

    ModelManagerAdapter* adapter = getAdapter();
    if (adapter == nullptr)
        return {false, "Write operations not supported by this provider"};

    bool result = adapter->deleteModel(name);

    if (result) {
        ModelChangeEvent event;
        event.type = ModelChangeType::Removed;
        event.modelName = name;
        notifyModelChanged(event);
    }

    return {result, result ? "" : "Failed to delete model '" + name + "'"};
}

OperationResult ModelEngine::renameModel(const std::string& oldName, const std::string& newName)
{
    if (!_provider->hasModel(oldName))
        return {false, "Model '" + oldName + "' not found"};

    if (_provider->hasModel(newName))
        return {false, "Model '" + newName + "' already exists"};

    ModelManagerAdapter* adapter = getAdapter();
    if (adapter == nullptr)
        return {false, "Write operations not supported by this provider"};

    bool result = adapter->renameModel(oldName, newName);

    if (result) {
        ModelChangeEvent event;
        event.type = ModelChangeType::Renamed;
        event.modelName = newName;
        event.oldName = oldName;
        notifyModelChanged(event);
    }

    return {result, result ? "" : "Failed to rename model"};
}

OperationResult ModelEngine::updateModelProperty(const std::string& name, const std::string& key, const std::string& value)
{
    Model* m = findModel(name);
    if (m == nullptr)
        return {false, "Model '" + name + "' not found"};

    m->SetProperty(wxString(key), wxString(value), true);

    ModelChangeEvent event;
    event.type = ModelChangeType::PropertyChanged;
    event.modelName = name;
    event.propertyKey = key;
    event.propertyValue = value;
    notifyModelChanged(event);

    return {true, ""};
}

// --- Smart Remote (Legacy Build) ---

int ModelEngine::getSmartRemote(const std::string& name) const
{
    Model* m = findModel(name);
    if (m == nullptr) return 0;
    return m->GetSmartRemote();
}

std::string ModelEngine::getSmartRemoteType(const std::string& name) const
{
    Model* m = findModel(name);
    if (m == nullptr) return "";
    return m->GetSmartRemoteType();
}

OperationResult ModelEngine::setSmartRemote(const std::string& name, int smartRemote)
{
    Model* m = findModel(name);
    if (m == nullptr)
        return {false, "Model '" + name + "' not found"};

    m->SetSmartRemote(smartRemote);

    ModelChangeEvent event;
    event.type = ModelChangeType::PropertyChanged;
    event.modelName = name;
    event.propertyKey = "SmartRemote";
    event.propertyValue = std::to_string(smartRemote);
    notifyModelChanged(event);

    return {true, ""};
}

OperationResult ModelEngine::setSmartRemoteType(const std::string& name, const std::string& type)
{
    Model* m = findModel(name);
    if (m == nullptr)
        return {false, "Model '" + name + "' not found"};

    m->SetSmartRemoteType(type);

    ModelChangeEvent event;
    event.type = ModelChangeType::PropertyChanged;
    event.modelName = name;
    event.propertyKey = "SmartRemoteType";
    event.propertyValue = type;
    notifyModelChanged(event);

    return {true, ""};
}

// --- Submodels ---

std::vector<SubmodelInfo> ModelEngine::getSubmodels(const std::string& modelName) const
{
    std::vector<SubmodelInfo> result;
    Model* m = findModel(modelName);
    if (m == nullptr)
        return result;

    const auto& submodels = m->GetSubModels();
    result.reserve(submodels.size());

    for (const auto* sm : submodels) {
        SubmodelInfo info;
        info.name = sm->GetName();
        info.fullName = sm->GetFullName();
        info.nodeCount = sm->GetNodeCount();
        info.channelCount = sm->GetChanCount();
        result.push_back(info);
    }

    return result;
}

bool ModelEngine::hasSubmodel(const std::string& modelName, const std::string& submodelName) const
{
    Model* m = findModel(modelName);
    if (m == nullptr)
        return false;
    return m->GetSubModel(submodelName) != nullptr;
}

SubmodelDefinition ModelEngine::getSubmodelDefinition(const std::string& modelName, const std::string& submodelName) const
{
    SubmodelDefinition def;
    Model* m = findModel(modelName);
    if (m == nullptr) return def;
    wxXmlNode* xml = m->GetModelXml();
    if (xml == nullptr) return def;
    for (wxXmlNode* child = xml->GetChildren(); child != nullptr; child = child->GetNext()) {
        if (child->GetName() == "subModel" && child->GetAttribute("name") == wxString(submodelName)) {
            def.name = submodelName;
            def.isRanges = (child->GetAttribute("type", "ranges") == "ranges");
            def.vertical = (child->GetAttribute("layout") == "vertical");
            def.bufferStyle = child->GetAttribute("bufferstyle", "Default").ToStdString();
            def.subBuffer = child->GetAttribute("subBuffer").ToStdString();
            if (def.isRanges) {
                for (int x = 0; child->HasAttribute(wxString::Format("line%d", x)); x++) {
                    def.strands.push_back(child->GetAttribute(wxString::Format("line%d", x)).ToStdString());
                }
            }
            return def;
        }
    }
    return def;
}

OperationResult ModelEngine::setSubmodel(const std::string& modelName, const std::string& submodelName, const SubmodelDefinition& definition)
{
    Model* m = findModel(modelName);
    if (m == nullptr) return {false, "Model '" + modelName + "' not found"};
    wxXmlNode* xml = m->GetModelXml();
    if (xml == nullptr) return {false, "Model XML not available"};
    wxXmlNode* smNode = nullptr;
    for (wxXmlNode* child = xml->GetChildren(); child != nullptr; child = child->GetNext()) {
        if (child->GetName() == "subModel" && child->GetAttribute("name") == wxString(submodelName)) {
            smNode = child;
            break;
        }
    }
    if (smNode == nullptr) {
        smNode = new wxXmlNode(wxXML_ELEMENT_NODE, "subModel");
        smNode->AddAttribute("name", submodelName);
        xml->AddChild(smNode);
    }
    // Clear old line attributes
    for (int x = 0; smNode->HasAttribute(wxString::Format("line%d", x)); x++) {
        smNode->DeleteAttribute(wxString::Format("line%d", x));
    }
    smNode->DeleteAttribute("subBuffer");
    // Set/update attributes via delete+add pattern
    auto setA = [&smNode](const wxString& key, const wxString& value) {
        if (smNode->HasAttribute(key)) smNode->DeleteAttribute(key);
        smNode->AddAttribute(key, value);
    };
    setA("type", definition.isRanges ? "ranges" : "subbuffer");
    setA("layout", definition.vertical ? "vertical" : "horizontal");
    setA("bufferstyle", definition.bufferStyle.empty() ? "Default" : definition.bufferStyle);
    if (definition.isRanges) {
        for (size_t i = 0; i < definition.strands.size(); i++)
            smNode->AddAttribute(wxString::Format("line%d", (int)i), definition.strands[i]);
    } else {
        smNode->AddAttribute("subBuffer", definition.subBuffer);
    }
    m->RemoveSubModel(submodelName);
    m->ParseSubModel(smNode);
    ModelChangeEvent evt;
    evt.type = ModelChangeType::Modified;
    evt.modelName = modelName;
    notifyModelChanged(evt);
    return {true, ""};
}

OperationResult ModelEngine::deleteSubmodel(const std::string& modelName, const std::string& submodelName)
{
    Model* m = findModel(modelName);
    if (m == nullptr) return {false, "Model '" + modelName + "' not found"};
    wxXmlNode* xml = m->GetModelXml();
    if (xml == nullptr) return {false, "Model XML not available"};
    for (wxXmlNode* child = xml->GetChildren(); child != nullptr; child = child->GetNext()) {
        if (child->GetName() == "subModel" && child->GetAttribute("name") == wxString(submodelName)) {
            xml->RemoveChild(child);
            delete child;
            m->RemoveSubModel(submodelName);
            ModelChangeEvent evt;
            evt.type = ModelChangeType::Modified;
            evt.modelName = modelName;
            notifyModelChanged(evt);
            return {true, ""};
        }
    }
    return {false, "Submodel '" + submodelName + "' not found"};
}

OperationResult ModelEngine::renameSubmodel(const std::string& modelName, const std::string& oldName, const std::string& newName)
{
    Model* m = findModel(modelName);
    if (m == nullptr) return {false, "Model '" + modelName + "' not found"};
    if (m->GetSubModel(oldName) == nullptr) return {false, "Submodel '" + oldName + "' not found"};
    if (m->GetSubModel(newName) != nullptr) return {false, "Submodel '" + newName + "' already exists"};
    wxXmlNode* xml = m->GetModelXml();
    if (xml == nullptr) return {false, "Model XML not available"};
    for (wxXmlNode* child = xml->GetChildren(); child != nullptr; child = child->GetNext()) {
        if (child->GetName() == "subModel" && child->GetAttribute("name") == wxString(oldName)) {
            child->DeleteAttribute("name");
            child->AddAttribute("name", newName);
            m->RemoveSubModel(oldName);
            m->ParseSubModel(child);
            ModelChangeEvent evt;
            evt.type = ModelChangeType::Modified;
            evt.modelName = modelName;
            notifyModelChanged(evt);
            return {true, ""};
        }
    }
    return {false, "Submodel XML node not found"};
}

// --- Groups ---

std::vector<ModelGroupInfo> ModelEngine::getModelGroups() const
{
    std::vector<ModelGroupInfo> result;
    auto groupNames = _provider->getGroupNames();
    for (const auto& name : groupNames) {
        Model* m = _provider->getModel(name);
        if (m != nullptr) {
            ModelGroup* grp = dynamic_cast<ModelGroup*>(m);
            if (grp != nullptr) {
                ModelGroupInfo info;
                info.name = grp->GetName();
                info.modelNames = grp->ModelNames();
                result.push_back(info);
            }
        }
    }
    return result;
}

ModelGroupInfo ModelEngine::getModelGroup(const std::string& groupName) const
{
    ModelGroupInfo info;
    Model* m = _provider->getModel(groupName);
    if (m == nullptr || m->GetDisplayAs() != "ModelGroup")
        return info;

    ModelGroup* grp = dynamic_cast<ModelGroup*>(m);
    if (grp == nullptr)
        return info;

    info.name = grp->GetName();
    info.modelNames = grp->ModelNames();
    return info;
}

std::vector<std::string> ModelEngine::getGroupsContainingModel(const std::string& modelName) const
{
    std::vector<std::string> result;
    Model* model = _provider->getModel(modelName);
    if (model == nullptr)
        return result;

    ModelManagerAdapter* adapter = getAdapter();
    if (adapter != nullptr) {
        return adapter->getGroupsContainingModel(model);
    }

    // Fallback: iterate through groups to find ones containing this model
    auto groupNames = _provider->getGroupNames();
    for (const auto& groupName : groupNames) {
        Model* grpModel = _provider->getModel(groupName);
        if (grpModel != nullptr) {
            ModelGroup* grp = dynamic_cast<ModelGroup*>(grpModel);
            if (grp != nullptr) {
                auto modelNames = grp->ModelNames();
                if (std::find(modelNames.begin(), modelNames.end(), modelName) != modelNames.end()) {
                    result.push_back(groupName);
                }
            }
        }
    }
    return result;
}

// --- Group CRUD ---

OperationResult ModelEngine::createModelGroup(const std::string& groupName,
                                              const std::vector<std::string>& modelNames)
{
    if (_provider->hasModel(groupName))
        return {false, "A model or group named '" + groupName + "' already exists"};

    ModelManagerAdapter* adapter = getAdapter();
    if (adapter == nullptr)
        return {false, "Write operations not supported by this provider"};

    bool ok = adapter->createModelGroup(groupName, modelNames);
    if (ok) {
        ModelChangeEvent event;
        event.type = ModelChangeType::Added;
        event.modelName = groupName;
        notifyModelChanged(event);
    }
    return {ok, ok ? "" : "Failed to create model group '" + groupName + "'"};
}

OperationResult ModelEngine::deleteModelGroup(const std::string& groupName)
{
    Model* m = findModel(groupName);
    if (m == nullptr || m->GetDisplayAs() != "ModelGroup")
        return {false, "Group '" + groupName + "' not found"};

    ModelManagerAdapter* adapter = getAdapter();
    if (adapter == nullptr)
        return {false, "Write operations not supported by this provider"};

    bool ok = adapter->deleteModel(groupName);
    if (ok) {
        ModelChangeEvent event;
        event.type = ModelChangeType::Removed;
        event.modelName = groupName;
        notifyModelChanged(event);
    }
    return {ok, ok ? "" : "Failed to delete group '" + groupName + "'"};
}

OperationResult ModelEngine::renameModelGroup(const std::string& oldName, const std::string& newName)
{
    Model* m = findModel(oldName);
    if (m == nullptr || m->GetDisplayAs() != "ModelGroup")
        return {false, "Group '" + oldName + "' not found"};

    if (_provider->hasModel(newName))
        return {false, "A model or group named '" + newName + "' already exists"};

    ModelManagerAdapter* adapter = getAdapter();
    if (adapter == nullptr)
        return {false, "Write operations not supported by this provider"};

    bool ok = adapter->renameModel(oldName, newName);
    if (ok) {
        ModelChangeEvent event;
        event.type = ModelChangeType::Renamed;
        event.modelName = newName;
        event.oldName = oldName;
        notifyModelChanged(event);
    }
    return {ok, ok ? "" : "Failed to rename group '" + oldName + "'"};
}

OperationResult ModelEngine::addModelToGroup(const std::string& groupName, const std::string& modelName)
{
    Model* m = findModel(groupName);
    if (m == nullptr || m->GetDisplayAs() != "ModelGroup")
        return {false, "Group '" + groupName + "' not found"};

    ModelGroup* grp = dynamic_cast<ModelGroup*>(m);
    if (grp == nullptr)
        return {false, "'" + groupName + "' is not a model group"};

    grp->AddModel(modelName);

    ModelChangeEvent event;
    event.type = ModelChangeType::Modified;
    event.modelName = groupName;
    notifyModelChanged(event);

    return {true, ""};
}

OperationResult ModelEngine::removeModelFromGroup(const std::string& groupName, const std::string& modelName)
{
    Model* m = findModel(groupName);
    if (m == nullptr || m->GetDisplayAs() != "ModelGroup")
        return {false, "Group '" + groupName + "' not found"};

    ModelGroup* grp = dynamic_cast<ModelGroup*>(m);
    if (grp == nullptr)
        return {false, "'" + groupName + "' is not a model group"};

    grp->ModelRemoved(modelName);

    ModelChangeEvent event;
    event.type = ModelChangeType::Modified;
    event.modelName = groupName;
    notifyModelChanged(event);

    return {true, ""};
}

// --- Dimming Curves (legacy build) ---

std::map<std::string, std::map<std::string, std::string>> ModelEngine::getDimmingInfo(
    const std::string& modelName) const {
    Model* m = findModel(modelName);
    if (!m) return {};
    return m->GetDimmingInfo();
}

OperationResult ModelEngine::setDimmingInfo(const std::string& modelName,
    const std::map<std::string, std::map<std::string, std::string>>& dimmingInfo) {
    Model* m = findModel(modelName);
    if (!m) return {false, "Model '" + modelName + "' not found"};

    // Remove existing dimmingCurve XML node
    wxXmlNode* f = m->GetModelXml()->GetChildren();
    while (f != nullptr) {
        if ("dimmingCurve" == f->GetName()) {
            m->GetModelXml()->RemoveChild(f);
            delete f;
            f = m->GetModelXml()->GetChildren();
        } else {
            f = f->GetNext();
        }
    }

    // Write new dimmingCurve node if info is not empty
    if (!dimmingInfo.empty()) {
        wxXmlNode* dcNode = new wxXmlNode(wxXML_ELEMENT_NODE, "dimmingCurve");
        m->GetModelXml()->AddChild(dcNode);
        for (const auto& channel : dimmingInfo) {
            wxXmlNode* chNode = new wxXmlNode(wxXML_ELEMENT_NODE, channel.first);
            dcNode->AddChild(chNode);
            for (const auto& param : channel.second) {
                chNode->AddAttribute(param.first, param.second);
            }
        }
    }

    ModelChangeEvent event;
    event.type = ModelChangeType::PropertyChanged;
    event.modelName = modelName;
    notifyModelChanged(event);

    return {true, ""};
}

// --- Position & Geometry ---

ModelEngine::BoundingBox ModelEngine::getModelBounds(const std::string& name) const
{
    BoundingBox box;
    Model* m = findModel(name);
    if (m == nullptr)
        return box;

    // Use the screen location to get bounds
    const ModelScreenLocation& loc = m->GetModelScreenLocation();
    box.minX = loc.GetLeft();
    box.maxX = loc.GetRight();
    box.minY = loc.GetBottom();
    box.maxY = loc.GetTop();
    box.minZ = loc.GetFront();
    box.maxZ = loc.GetBack();

    return box;
}

// --- Group Buffer Nodes (legacy) ---

std::vector<ModelEngine::GroupMemberNodes> ModelEngine::getGroupBufferNodes(
    const std::string& groupName) const
{
    // Legacy build: not used (sidebar preview uses Model objects directly)
    return {};
}

// --- Face Definitions (legacy) ---

std::vector<std::string> ModelEngine::getFaceNames(const std::string& modelName) const {
    Model* m = findModel(modelName);
    if (!m) return {};
    std::vector<std::string> names;
    for (const auto& face : m->GetFaceInfo()) {
        names.push_back(face.first);
    }
    return names;
}

std::map<std::string, std::string> ModelEngine::getFaceDefinition(
    const std::string& modelName, const std::string& faceName) const {
    Model* m = findModel(modelName);
    if (!m) return {};
    const auto& faceInfo = m->GetFaceInfo();
    auto it = faceInfo.find(faceName);
    if (it != faceInfo.end()) return it->second;
    return {};
}

std::map<std::string, std::map<std::string, std::string>> ModelEngine::getAllFaceDefinitions(
    const std::string& modelName) const {
    Model* m = findModel(modelName);
    if (!m) return {};
    return m->GetFaceInfo();
}

OperationResult ModelEngine::setFaceDefinition(const std::string& modelName, const std::string& faceName,
                                               const std::map<std::string, std::string>& definition) {
    Model* m = findModel(modelName);
    if (!m) return {false, "Model not found"};
    auto faceInfo = m->GetFaceInfo();
    faceInfo[faceName] = definition;
    m->SetFaceInfo(faceInfo);
    return {true, ""};
}

OperationResult ModelEngine::setAllFaceDefinitions(const std::string& modelName,
    const std::map<std::string, std::map<std::string, std::string>>& definitions) {
    Model* m = findModel(modelName);
    if (!m) return {false, "Model not found"};
    m->SetFaceInfo(definitions);
    return {true, ""};
}

OperationResult ModelEngine::deleteFaceDefinition(const std::string& modelName, const std::string& faceName) {
    Model* m = findModel(modelName);
    if (!m) return {false, "Model not found"};
    auto faceInfo = m->GetFaceInfo();
    auto it = faceInfo.find(faceName);
    if (it == faceInfo.end()) return {false, "Face definition not found"};
    faceInfo.erase(it);
    m->SetFaceInfo(faceInfo);
    return {true, ""};
}

OperationResult ModelEngine::renameFaceDefinition(const std::string& modelName,
                                                  const std::string& oldName, const std::string& newName) {
    Model* m = findModel(modelName);
    if (!m) return {false, "Model not found"};
    auto faceInfo = m->GetFaceInfo();
    auto it = faceInfo.find(oldName);
    if (it == faceInfo.end()) return {false, "Face definition not found"};
    if (faceInfo.find(newName) != faceInfo.end()) return {false, "Name already exists"};
    auto data = std::move(it->second);
    faceInfo.erase(it);
    faceInfo[newName] = std::move(data);
    m->SetFaceInfo(faceInfo);
    return {true, ""};
}

// --- Listener Management ---

void ModelEngine::addListener(ModelEngineListener* listener)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    _listeners.push_back(listener);
}

void ModelEngine::removeListener(ModelEngineListener* listener)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    _listeners.erase(
        std::remove(_listeners.begin(), _listeners.end(), listener),
        _listeners.end());
}

void ModelEngine::notifyModelChanged(const ModelChangeEvent& event)
{
    std::lock_guard<std::mutex> lock(_listenerMutex);
    for (auto* listener : _listeners) {
        switch (event.type) {
            case ModelChangeType::Added:
                listener->onModelAdded(event);
                break;
            case ModelChangeType::Removed:
                listener->onModelRemoved(event);
                break;
            case ModelChangeType::Modified:
                listener->onModelModified(event);
                break;
            case ModelChangeType::Renamed:
                listener->onModelRenamed(event);
                break;
            case ModelChangeType::PropertyChanged:
                listener->onModelPropertyChanged(event);
                break;
        }
    }
}

#endif // XLIGHTS_NATIVE

} // namespace xlEngine
