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
 * @file StringUtils.h
 * @brief String utility functions for xlCore.
 *
 * This header provides common string manipulation utilities designed
 * to work with std::string (UTF-8). These replace various wxString
 * operations used throughout xLights.
 */

#include <string>
#include <string_view>
#include <vector>
#include <algorithm>
#include <cctype>
#include <charconv>
#include <sstream>
#include <iomanip>
#include <optional>

namespace xlCore {
namespace strings {

/**
 * @brief Trim whitespace from the left side of a string.
 */
inline std::string trimLeft(std::string_view str) {
    auto it = std::find_if(str.begin(), str.end(), [](unsigned char ch) {
        return !std::isspace(ch);
    });
    return std::string(it, str.end());
}

/**
 * @brief Trim whitespace from the right side of a string.
 */
inline std::string trimRight(std::string_view str) {
    auto it = std::find_if(str.rbegin(), str.rend(), [](unsigned char ch) {
        return !std::isspace(ch);
    });
    return std::string(str.begin(), it.base());
}

/**
 * @brief Trim whitespace from both sides of a string.
 */
inline std::string trim(std::string_view str) {
    return trimLeft(trimRight(str));
}

/**
 * @brief Convert string to lowercase.
 */
inline std::string toLower(std::string_view str) {
    std::string result(str);
    std::transform(result.begin(), result.end(), result.begin(),
                   [](unsigned char c) { return std::tolower(c); });
    return result;
}

/**
 * @brief Convert string to uppercase.
 */
inline std::string toUpper(std::string_view str) {
    std::string result(str);
    std::transform(result.begin(), result.end(), result.begin(),
                   [](unsigned char c) { return std::toupper(c); });
    return result;
}

/**
 * @brief Case-insensitive string comparison.
 * @return true if strings are equal (ignoring case)
 */
inline bool equalsIgnoreCase(std::string_view a, std::string_view b) {
    if (a.size() != b.size()) return false;
    return std::equal(a.begin(), a.end(), b.begin(),
                      [](unsigned char ca, unsigned char cb) {
                          return std::tolower(ca) == std::tolower(cb);
                      });
}

/**
 * @brief Check if string starts with prefix.
 */
inline bool startsWith(std::string_view str, std::string_view prefix) {
    if (prefix.size() > str.size()) return false;
    return str.substr(0, prefix.size()) == prefix;
}

/**
 * @brief Check if string starts with prefix (case-insensitive).
 */
inline bool startsWithIgnoreCase(std::string_view str, std::string_view prefix) {
    if (prefix.size() > str.size()) return false;
    return equalsIgnoreCase(str.substr(0, prefix.size()), prefix);
}

/**
 * @brief Check if string ends with suffix.
 */
inline bool endsWith(std::string_view str, std::string_view suffix) {
    if (suffix.size() > str.size()) return false;
    return str.substr(str.size() - suffix.size()) == suffix;
}

/**
 * @brief Check if string ends with suffix (case-insensitive).
 */
inline bool endsWithIgnoreCase(std::string_view str, std::string_view suffix) {
    if (suffix.size() > str.size()) return false;
    return equalsIgnoreCase(str.substr(str.size() - suffix.size()), suffix);
}

/**
 * @brief Check if string contains substring.
 */
inline bool contains(std::string_view str, std::string_view substr) {
    return str.find(substr) != std::string_view::npos;
}

/**
 * @brief Check if string contains substring (case-insensitive).
 */
inline bool containsIgnoreCase(std::string_view str, std::string_view substr) {
    return toLower(str).find(toLower(substr)) != std::string::npos;
}

/**
 * @brief Split string by delimiter.
 */
inline std::vector<std::string> split(std::string_view str, char delimiter) {
    std::vector<std::string> result;
    size_t start = 0;
    size_t end;

    while ((end = str.find(delimiter, start)) != std::string_view::npos) {
        result.emplace_back(str.substr(start, end - start));
        start = end + 1;
    }
    result.emplace_back(str.substr(start));

    return result;
}

/**
 * @brief Split string by string delimiter.
 */
inline std::vector<std::string> split(std::string_view str, std::string_view delimiter) {
    std::vector<std::string> result;
    if (delimiter.empty()) {
        result.emplace_back(str);
        return result;
    }

    size_t start = 0;
    size_t end;

    while ((end = str.find(delimiter, start)) != std::string_view::npos) {
        result.emplace_back(str.substr(start, end - start));
        start = end + delimiter.size();
    }
    result.emplace_back(str.substr(start));

    return result;
}

/**
 * @brief Join strings with delimiter.
 */
inline std::string join(const std::vector<std::string>& parts, std::string_view delimiter) {
    if (parts.empty()) return "";

    std::string result = parts[0];
    for (size_t i = 1; i < parts.size(); ++i) {
        result += delimiter;
        result += parts[i];
    }
    return result;
}

/**
 * @brief Replace all occurrences of a substring.
 */
inline std::string replaceAll(std::string_view str, std::string_view from, std::string_view to) {
    if (from.empty()) return std::string(str);

    std::string result;
    result.reserve(str.size());

    size_t start = 0;
    size_t pos;
    while ((pos = str.find(from, start)) != std::string_view::npos) {
        result.append(str.substr(start, pos - start));
        result.append(to);
        start = pos + from.size();
    }
    result.append(str.substr(start));

    return result;
}

/**
 * @brief Parse integer from string.
 * @return Parsed value or std::nullopt if parsing fails
 */
inline std::optional<int> parseInt(std::string_view str) {
    str = trim(str);
    if (str.empty()) return std::nullopt;

    int value;
    auto result = std::from_chars(str.data(), str.data() + str.size(), value);
    if (result.ec == std::errc() && result.ptr == str.data() + str.size()) {
        return value;
    }
    return std::nullopt;
}

/**
 * @brief Parse integer with default value.
 */
inline int parseInt(std::string_view str, int defaultValue) {
    return parseInt(str).value_or(defaultValue);
}

/**
 * @brief Parse long from string.
 */
inline std::optional<long> parseLong(std::string_view str) {
    str = trim(str);
    if (str.empty()) return std::nullopt;

    long value;
    auto result = std::from_chars(str.data(), str.data() + str.size(), value);
    if (result.ec == std::errc() && result.ptr == str.data() + str.size()) {
        return value;
    }
    return std::nullopt;
}

/**
 * @brief Parse double from string.
 */
inline std::optional<double> parseDouble(std::string_view str) {
    str = trim(str);
    if (str.empty()) return std::nullopt;

    try {
        size_t pos;
        double value = std::stod(std::string(str), &pos);
        if (pos == str.size()) {
            return value;
        }
    } catch (...) {}

    return std::nullopt;
}

/**
 * @brief Parse double with default value.
 */
inline double parseDouble(std::string_view str, double defaultValue) {
    return parseDouble(str).value_or(defaultValue);
}

/**
 * @brief Parse boolean from string.
 * Accepts: "true", "false", "yes", "no", "1", "0" (case-insensitive)
 */
inline std::optional<bool> parseBool(std::string_view str) {
    str = trim(str);
    std::string lower = toLower(str);

    if (lower == "true" || lower == "yes" || lower == "1") {
        return true;
    }
    if (lower == "false" || lower == "no" || lower == "0") {
        return false;
    }
    return std::nullopt;
}

/**
 * @brief Parse boolean with default value.
 */
inline bool parseBool(std::string_view str, bool defaultValue) {
    return parseBool(str).value_or(defaultValue);
}

/**
 * @brief Convert integer to string.
 */
inline std::string toString(int value) {
    return std::to_string(value);
}

/**
 * @brief Convert double to string with precision.
 */
inline std::string toString(double value, int precision = 6) {
    std::ostringstream ss;
    ss << std::fixed << std::setprecision(precision) << value;
    return ss.str();
}

/**
 * @brief Convert boolean to string.
 */
inline std::string toString(bool value) {
    return value ? "true" : "false";
}

/**
 * @brief Format string (printf-style).
 * @note Limited implementation - for complex formatting use fmt library
 */
template<typename... Args>
std::string format(const char* fmt, Args... args) {
    int size = std::snprintf(nullptr, 0, fmt, args...) + 1;
    if (size <= 0) return "";

    std::vector<char> buf(size);
    std::snprintf(buf.data(), size, fmt, args...);
    return std::string(buf.data(), buf.data() + size - 1);
}

/**
 * @brief URL-encode a string.
 */
inline std::string urlEncode(std::string_view str) {
    std::ostringstream encoded;
    encoded << std::hex << std::uppercase;

    for (unsigned char c : str) {
        if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
            encoded << c;
        } else if (c == ' ') {
            encoded << '+';
        } else {
            encoded << '%' << std::setw(2) << std::setfill('0') << static_cast<int>(c);
        }
    }

    return encoded.str();
}

/**
 * @brief URL-decode a string.
 */
inline std::string urlDecode(std::string_view str) {
    std::string decoded;
    decoded.reserve(str.size());

    for (size_t i = 0; i < str.size(); ++i) {
        if (str[i] == '+') {
            decoded += ' ';
        } else if (str[i] == '%' && i + 2 < str.size()) {
            int high = std::isxdigit(str[i + 1]) ? (std::isdigit(str[i + 1]) ? str[i + 1] - '0' : std::tolower(str[i + 1]) - 'a' + 10) : -1;
            int low = std::isxdigit(str[i + 2]) ? (std::isdigit(str[i + 2]) ? str[i + 2] - '0' : std::tolower(str[i + 2]) - 'a' + 10) : -1;
            if (high >= 0 && low >= 0) {
                decoded += static_cast<char>(high * 16 + low);
                i += 2;
            } else {
                decoded += str[i];
            }
        } else {
            decoded += str[i];
        }
    }

    return decoded;
}

/**
 * @brief Escape special characters for XML/HTML.
 */
inline std::string escapeXml(std::string_view str) {
    std::string result;
    result.reserve(str.size() * 1.2); // Estimate 20% growth

    for (char c : str) {
        switch (c) {
            case '&':  result += "&amp;";  break;
            case '<':  result += "&lt;";   break;
            case '>':  result += "&gt;";   break;
            case '"':  result += "&quot;"; break;
            case '\'': result += "&apos;"; break;
            default:   result += c;        break;
        }
    }

    return result;
}

/**
 * @brief Remove ANSI escape codes from string.
 */
inline std::string stripAnsi(std::string_view str) {
    std::string result;
    result.reserve(str.size());

    bool inEscape = false;
    for (size_t i = 0; i < str.size(); ++i) {
        if (str[i] == '\x1b' && i + 1 < str.size() && str[i + 1] == '[') {
            inEscape = true;
            ++i; // Skip '['
        } else if (inEscape) {
            if (std::isalpha(static_cast<unsigned char>(str[i]))) {
                inEscape = false;
            }
        } else {
            result += str[i];
        }
    }

    return result;
}

} // namespace strings
} // namespace xlCore
