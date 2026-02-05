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

// Generate node positions for a model from its XML attributes.
// This approximates the legacy Model class node generation using only the
// attributes stored in rgbeffects.xml — no Model objects required.
static std::vector<NodeCoord> generateNodesFromAttributes(
    const std::map<std::string, std::string>& attrs)
{
    std::string type = attrStr(attrs, "DisplayAs");
    float wx = attrFloat(attrs, "WorldPosX");
    float wy = attrFloat(attrs, "WorldPosY");
    float wz = attrFloat(attrs, "WorldPosZ");

    int parm1 = attrInt(attrs, "parm1", 1);
    int parm2 = attrInt(attrs, "parm2", 1);
    if (parm1 < 1) parm1 = 1;
    if (parm2 < 1) parm2 = 1;

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
        // parm3 = strands per string (zig-zag)
        int parm3 = attrInt(attrs, "parm3", 1);
        if (parm3 < 1) parm3 = 1;

        int cols, rows;
        if (type == "Vert Matrix") {
            cols = parm1 * parm3;
            rows = parm2 / parm3;
        } else {
            cols = parm2 / parm3;
            rows = parm1 * parm3;
        }
        if (cols < 1) cols = 1;
        if (rows < 1) rows = 1;

        bool hasThreePoint = (std::abs(x2) > 0.1f || std::abs(y2) > 0.1f ||
                              std::abs(x3) > 0.1f || std::abs(y3) > 0.1f);

        nodes.reserve(cols * rows);
        if (hasThreePoint) {
            // ThreePointScreenLocation: X2/Y2 define one axis, X3/Y3 the other
            for (int r = 0; r < rows; r++) {
                for (int c = 0; c < cols; c++) {
                    float ct = (cols > 1) ? (float)c / (float)(cols - 1) : 0.5f;
                    float rt = (rows > 1) ? (float)r / (float)(rows - 1) : 0.5f;
                    NodeCoord nc;
                    nc.x = wx + x2 * ct + x3 * rt;
                    nc.y = wy + y2 * ct + y3 * rt;
                    nc.z = wz + z2 * ct;
                    nc.bufX = c;
                    nc.bufY = r;
                    nodes.push_back(nc);
                }
            }
        } else {
            // BoxedScreenLocation: use ScaleX/ScaleY centered at WorldPos
            float scaleX = attrFloat(attrs, "ScaleX", 1.0f);
            float scaleY = attrFloat(attrs, "ScaleY", 1.0f);
            if (std::abs(scaleX) < 0.001f) scaleX = 1.0f;
            if (std::abs(scaleY) < 0.001f) scaleY = 1.0f;

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
        float innerPercent = attrFloat(attrs, "starInnerPercent", -1.0f);

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
        float scaleX = attrFloat(attrs, "ScaleX", 0.0f);
        float scaleY = attrFloat(attrs, "ScaleY", 0.0f);

        bool hasScale = (std::abs(scaleX) > 0.01f || std::abs(scaleY) > 0.01f);
        bool hasExtent = (std::abs(x2) > 0.1f || std::abs(y2) > 0.1f);

        if (hasScale) {
            // BoxedScreenLocation: grid of nodes centered at WorldPos
            // Each node is spaced scaleX apart horizontally, scaleY apart vertically
            int cols = (parm2 > 0) ? parm2 : 1;
            int rows = (parm1 > 0) ? parm1 : 1;
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
            int totalNodes = parm1 * parm2;
            if (totalNodes < 1) totalNodes = 1;
            if (totalNodes > 5000) totalNodes = 5000;

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
        } else {
            // No extent info — place a single representative node
            NodeCoord nc;
            nc.x = wx;
            nc.y = wy;
            nc.z = wz;
            nodes.push_back(nc);
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
    int p1 = attrInt(attrs, "parm1", 1);
    int p2 = attrInt(attrs, "parm2", 1);
    uint32_t count = (uint32_t)(p1 * p2);
    return (count > 0) ? count : 1;
}

uint32_t ModelEngine::getModelChannelCount(const std::string& name) const
{
    return 0;
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
    return {false, "Native build: property update not yet implemented"};
}

std::vector<SubmodelInfo> ModelEngine::getSubmodels(const std::string& modelName) const
{
    return {};
}

bool ModelEngine::hasSubmodel(const std::string& modelName, const std::string& submodelName) const
{
    return false;
}

std::vector<ModelGroupInfo> ModelEngine::getModelGroups() const
{
    return {};
}

ModelGroupInfo ModelEngine::getModelGroup(const std::string& groupName) const
{
    return ModelGroupInfo();
}

std::vector<std::string> ModelEngine::getGroupsContainingModel(const std::string& modelName) const
{
    return {};
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
