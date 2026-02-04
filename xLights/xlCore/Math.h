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
 * @file Math.h
 * @brief Mathematical types for 2D/3D graphics operations.
 *
 * This header provides pure C++17/20 replacements for wxPoint, wxRealPoint,
 * and wxRect, plus Vec2/Vec3 classes for vector math operations.
 * All types are designed to be constexpr-friendly and thread-safe.
 */

#include <cmath>
#include <algorithm>
#include <type_traits>

namespace xlCore {

/**
 * @brief 2D integer point (replaces wxPoint).
 */
struct Point2D {
    int x = 0;
    int y = 0;

    constexpr Point2D() = default;
    constexpr Point2D(int x_, int y_) : x(x_), y(y_) {}

    constexpr bool operator==(const Point2D& other) const {
        return x == other.x && y == other.y;
    }

    constexpr bool operator!=(const Point2D& other) const {
        return !(*this == other);
    }

    constexpr Point2D operator+(const Point2D& other) const {
        return {x + other.x, y + other.y};
    }

    constexpr Point2D operator-(const Point2D& other) const {
        return {x - other.x, y - other.y};
    }

    constexpr Point2D operator*(int scale) const {
        return {x * scale, y * scale};
    }

    constexpr Point2D operator/(int scale) const {
        return {x / scale, y / scale};
    }

    constexpr Point2D& operator+=(const Point2D& other) {
        x += other.x;
        y += other.y;
        return *this;
    }

    constexpr Point2D& operator-=(const Point2D& other) {
        x -= other.x;
        y -= other.y;
        return *this;
    }

    constexpr Point2D operator-() const {
        return {-x, -y};
    }

    // Distance from origin
    float length() const {
        return std::sqrt(static_cast<float>(x * x + y * y));
    }

    // Squared distance (avoids sqrt)
    constexpr int lengthSquared() const {
        return x * x + y * y;
    }
};

/**
 * @brief 2D floating-point vector (replaces wxRealPoint).
 */
struct Vec2 {
    float x = 0.0f;
    float y = 0.0f;

    constexpr Vec2() = default;
    constexpr Vec2(float x_, float y_) : x(x_), y(y_) {}

    // Conversion from Point2D
    constexpr explicit Vec2(const Point2D& p) : x(static_cast<float>(p.x)), y(static_cast<float>(p.y)) {}

    constexpr bool operator==(const Vec2& other) const {
        return x == other.x && y == other.y;
    }

    constexpr bool operator!=(const Vec2& other) const {
        return !(*this == other);
    }

    constexpr Vec2 operator+(const Vec2& other) const {
        return {x + other.x, y + other.y};
    }

    constexpr Vec2 operator-(const Vec2& other) const {
        return {x - other.x, y - other.y};
    }

    constexpr Vec2 operator*(float scale) const {
        return {x * scale, y * scale};
    }

    constexpr Vec2 operator/(float scale) const {
        return {x / scale, y / scale};
    }

    constexpr Vec2& operator+=(const Vec2& other) {
        x += other.x;
        y += other.y;
        return *this;
    }

    constexpr Vec2& operator-=(const Vec2& other) {
        x -= other.x;
        y -= other.y;
        return *this;
    }

    constexpr Vec2& operator*=(float scale) {
        x *= scale;
        y *= scale;
        return *this;
    }

    constexpr Vec2& operator/=(float scale) {
        x /= scale;
        y /= scale;
        return *this;
    }

    constexpr Vec2 operator-() const {
        return {-x, -y};
    }

    // Dot product
    constexpr float dot(const Vec2& other) const {
        return x * other.x + y * other.y;
    }

    // 2D cross product (returns scalar, z-component of 3D cross)
    constexpr float cross(const Vec2& other) const {
        return x * other.y - y * other.x;
    }

    // Length
    float length() const {
        return std::sqrt(x * x + y * y);
    }

    // Squared length (avoids sqrt)
    constexpr float lengthSquared() const {
        return x * x + y * y;
    }

    // Normalized vector
    Vec2 normalized() const {
        float len = length();
        if (len < 1e-10f) return {0.0f, 0.0f};
        return {x / len, y / len};
    }

    // Linear interpolation
    constexpr Vec2 lerp(const Vec2& other, float t) const {
        return {x + (other.x - x) * t, y + (other.y - y) * t};
    }

    // Perpendicular vector (90 degrees counter-clockwise)
    constexpr Vec2 perpendicular() const {
        return {-y, x};
    }

    // Distance to another point
    float distanceTo(const Vec2& other) const {
        return (*this - other).length();
    }

    // Convert to Point2D (truncates)
    constexpr Point2D toPoint2D() const {
        return {static_cast<int>(x), static_cast<int>(y)};
    }

    // Static factories
    static constexpr Vec2 zero() { return {0.0f, 0.0f}; }
    static constexpr Vec2 one() { return {1.0f, 1.0f}; }
    static constexpr Vec2 unitX() { return {1.0f, 0.0f}; }
    static constexpr Vec2 unitY() { return {0.0f, 1.0f}; }
};

/**
 * @brief 3D floating-point vector.
 */
struct Vec3 {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;

    constexpr Vec3() = default;
    constexpr Vec3(float x_, float y_, float z_) : x(x_), y(y_), z(z_) {}

    // Conversion from Vec2 (z = 0)
    constexpr explicit Vec3(const Vec2& v, float z_ = 0.0f) : x(v.x), y(v.y), z(z_) {}

    constexpr bool operator==(const Vec3& other) const {
        return x == other.x && y == other.y && z == other.z;
    }

    constexpr bool operator!=(const Vec3& other) const {
        return !(*this == other);
    }

    constexpr Vec3 operator+(const Vec3& other) const {
        return {x + other.x, y + other.y, z + other.z};
    }

    constexpr Vec3 operator-(const Vec3& other) const {
        return {x - other.x, y - other.y, z - other.z};
    }

    constexpr Vec3 operator*(float scale) const {
        return {x * scale, y * scale, z * scale};
    }

    constexpr Vec3 operator/(float scale) const {
        return {x / scale, y / scale, z / scale};
    }

    constexpr Vec3& operator+=(const Vec3& other) {
        x += other.x;
        y += other.y;
        z += other.z;
        return *this;
    }

    constexpr Vec3& operator-=(const Vec3& other) {
        x -= other.x;
        y -= other.y;
        z -= other.z;
        return *this;
    }

    constexpr Vec3& operator*=(float scale) {
        x *= scale;
        y *= scale;
        z *= scale;
        return *this;
    }

    constexpr Vec3& operator/=(float scale) {
        x /= scale;
        y /= scale;
        z /= scale;
        return *this;
    }

    constexpr Vec3 operator-() const {
        return {-x, -y, -z};
    }

    // Dot product
    constexpr float dot(const Vec3& other) const {
        return x * other.x + y * other.y + z * other.z;
    }

    // Cross product
    constexpr Vec3 cross(const Vec3& other) const {
        return {
            y * other.z - z * other.y,
            z * other.x - x * other.z,
            x * other.y - y * other.x
        };
    }

    // Length
    float length() const {
        return std::sqrt(x * x + y * y + z * z);
    }

    // Squared length
    constexpr float lengthSquared() const {
        return x * x + y * y + z * z;
    }

    // Normalized vector
    Vec3 normalized() const {
        float len = length();
        if (len < 1e-10f) return {0.0f, 0.0f, 0.0f};
        return {x / len, y / len, z / len};
    }

    // Linear interpolation
    constexpr Vec3 lerp(const Vec3& other, float t) const {
        return {
            x + (other.x - x) * t,
            y + (other.y - y) * t,
            z + (other.z - z) * t
        };
    }

    // Distance to another point
    float distanceTo(const Vec3& other) const {
        return (*this - other).length();
    }

    // Project onto another vector
    Vec3 projectOnto(const Vec3& other) const {
        float denom = other.lengthSquared();
        if (denom < 1e-10f) return {0.0f, 0.0f, 0.0f};
        float scale = dot(other) / denom;
        return other * scale;
    }

    // Reflect around a normal
    constexpr Vec3 reflect(const Vec3& normal) const {
        return *this - normal * (2.0f * dot(normal));
    }

    // Get xy component as Vec2
    constexpr Vec2 xy() const {
        return {x, y};
    }

    // Static factories
    static constexpr Vec3 zero() { return {0.0f, 0.0f, 0.0f}; }
    static constexpr Vec3 one() { return {1.0f, 1.0f, 1.0f}; }
    static constexpr Vec3 unitX() { return {1.0f, 0.0f, 0.0f}; }
    static constexpr Vec3 unitY() { return {0.0f, 1.0f, 0.0f}; }
    static constexpr Vec3 unitZ() { return {0.0f, 0.0f, 1.0f}; }
};

/**
 * @brief 2D integer rectangle (replaces wxRect).
 */
struct Rect {
    int x = 0;
    int y = 0;
    int width = 0;
    int height = 0;

    constexpr Rect() = default;
    constexpr Rect(int x_, int y_, int w, int h) : x(x_), y(y_), width(w), height(h) {}
    constexpr Rect(const Point2D& pos, int w, int h) : x(pos.x), y(pos.y), width(w), height(h) {}

    constexpr bool operator==(const Rect& other) const {
        return x == other.x && y == other.y && width == other.width && height == other.height;
    }

    constexpr bool operator!=(const Rect& other) const {
        return !(*this == other);
    }

    // Position accessors
    constexpr Point2D position() const { return {x, y}; }
    constexpr Point2D topLeft() const { return {x, y}; }
    constexpr Point2D topRight() const { return {x + width, y}; }
    constexpr Point2D bottomLeft() const { return {x, y + height}; }
    constexpr Point2D bottomRight() const { return {x + width, y + height}; }
    constexpr Point2D center() const { return {x + width / 2, y + height / 2}; }

    // Edge accessors
    constexpr int left() const { return x; }
    constexpr int right() const { return x + width; }
    constexpr int top() const { return y; }
    constexpr int bottom() const { return y + height; }

    // Size
    constexpr int area() const { return width * height; }
    constexpr bool isEmpty() const { return width <= 0 || height <= 0; }

    // Point containment
    constexpr bool contains(int px, int py) const {
        return px >= x && px < x + width && py >= y && py < y + height;
    }

    constexpr bool contains(const Point2D& p) const {
        return contains(p.x, p.y);
    }

    // Rectangle containment
    constexpr bool contains(const Rect& other) const {
        return other.x >= x && other.y >= y &&
               other.right() <= right() && other.bottom() <= bottom();
    }

    // Intersection test
    constexpr bool intersects(const Rect& other) const {
        return x < other.right() && right() > other.x &&
               y < other.bottom() && bottom() > other.y;
    }

    // Get intersection rectangle
    constexpr Rect intersection(const Rect& other) const {
        int ix = std::max(x, other.x);
        int iy = std::max(y, other.y);
        int ir = std::min(right(), other.right());
        int ib = std::min(bottom(), other.bottom());

        if (ix >= ir || iy >= ib) {
            return {}; // Empty rect
        }

        return {ix, iy, ir - ix, ib - iy};
    }

    // Get union rectangle (bounding box)
    constexpr Rect boundingUnion(const Rect& other) const {
        if (isEmpty()) return other;
        if (other.isEmpty()) return *this;

        int ux = std::min(x, other.x);
        int uy = std::min(y, other.y);
        int ur = std::max(right(), other.right());
        int ub = std::max(bottom(), other.bottom());

        return {ux, uy, ur - ux, ub - uy};
    }

    // Expand by delta in all directions
    constexpr Rect inflated(int delta) const {
        return {x - delta, y - delta, width + 2 * delta, height + 2 * delta};
    }

    // Move by offset
    constexpr Rect offset(int dx, int dy) const {
        return {x + dx, y + dy, width, height};
    }

    constexpr Rect offset(const Point2D& delta) const {
        return offset(delta.x, delta.y);
    }

    // Setters
    constexpr void setPosition(int x_, int y_) { x = x_; y = y_; }
    constexpr void setPosition(const Point2D& p) { x = p.x; y = p.y; }
    constexpr void setSize(int w, int h) { width = w; height = h; }
};

/**
 * @brief 2D floating-point rectangle.
 */
struct RectF {
    float x = 0.0f;
    float y = 0.0f;
    float width = 0.0f;
    float height = 0.0f;

    constexpr RectF() = default;
    constexpr RectF(float x_, float y_, float w, float h) : x(x_), y(y_), width(w), height(h) {}
    constexpr RectF(const Vec2& pos, float w, float h) : x(pos.x), y(pos.y), width(w), height(h) {}

    // Conversion from Rect
    constexpr explicit RectF(const Rect& r)
        : x(static_cast<float>(r.x)), y(static_cast<float>(r.y)),
          width(static_cast<float>(r.width)), height(static_cast<float>(r.height)) {}

    // Position accessors
    constexpr Vec2 position() const { return {x, y}; }
    constexpr Vec2 center() const { return {x + width * 0.5f, y + height * 0.5f}; }

    // Edge accessors
    constexpr float left() const { return x; }
    constexpr float right() const { return x + width; }
    constexpr float top() const { return y; }
    constexpr float bottom() const { return y + height; }

    // Point containment
    constexpr bool contains(float px, float py) const {
        return px >= x && px < x + width && py >= y && py < y + height;
    }

    constexpr bool contains(const Vec2& p) const {
        return contains(p.x, p.y);
    }

    // Convert to integer Rect (truncates)
    constexpr Rect toRect() const {
        return {static_cast<int>(x), static_cast<int>(y),
                static_cast<int>(width), static_cast<int>(height)};
    }
};

// Scalar * vector operators
constexpr Vec2 operator*(float scale, const Vec2& v) {
    return v * scale;
}

constexpr Vec3 operator*(float scale, const Vec3& v) {
    return v * scale;
}

constexpr Point2D operator*(int scale, const Point2D& p) {
    return p * scale;
}

// Utility functions
namespace math {

constexpr float PI = 3.14159265358979323846f;
constexpr float TWO_PI = 2.0f * PI;
constexpr float HALF_PI = PI / 2.0f;
constexpr float DEG_TO_RAD = PI / 180.0f;
constexpr float RAD_TO_DEG = 180.0f / PI;

constexpr float toRadians(float degrees) {
    return degrees * DEG_TO_RAD;
}

constexpr float toDegrees(float radians) {
    return radians * RAD_TO_DEG;
}

template<typename T>
constexpr T clamp(T value, T minVal, T maxVal) {
    return std::max(minVal, std::min(value, maxVal));
}

template<typename T>
constexpr T lerp(T a, T b, float t) {
    return static_cast<T>(a + (b - a) * t);
}

// Smooth interpolation (smoothstep)
constexpr float smoothstep(float edge0, float edge1, float x) {
    float t = clamp((x - edge0) / (edge1 - edge0), 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
}

// Approximate equality for floating point
constexpr bool approxEqual(float a, float b, float epsilon = 1e-6f) {
    return std::abs(a - b) < epsilon;
}

} // namespace math

} // namespace xlCore
