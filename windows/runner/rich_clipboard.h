#ifndef RUNNER_RICH_CLIPBOARD_H_
#define RUNNER_RICH_CLIPBOARD_H_
#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>

inline std::string ClipboardHtml(const std::string& fragment) {
  const std::string prefix = "<html><body><!--StartFragment-->";
  const std::string suffix = "<!--EndFragment--></body></html>";
  auto header = [](size_t start, size_t end, size_t first, size_t last) {
    char buffer[256];
    std::snprintf(buffer, sizeof(buffer),
      "Version:0.9\r\nStartHTML:%010llu\r\nEndHTML:%010llu\r\nStartFragment:%010llu\r\nEndFragment:%010llu\r\n",
      static_cast<unsigned long long>(start), static_cast<unsigned long long>(end),
      static_cast<unsigned long long>(first), static_cast<unsigned long long>(last));
    return std::string(buffer);
  };
  const size_t start = header(0,0,0,0).size();
  const size_t first = start + prefix.size();
  const size_t last = first + fragment.size();
  return header(start, last + suffix.size(), first, last) + prefix + fragment + suffix;
}

inline HGLOBAL ClipboardMemory(const void* data, size_t bytes) {
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (!memory) return nullptr;
  void* target = GlobalLock(memory);
  if (!target) { GlobalFree(memory); return nullptr; }
  std::memcpy(target, data, bytes);
  GlobalUnlock(memory);
  return memory;
}

inline std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterRichClipboard(flutter::BinaryMessenger* messenger, HWND window) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
    messenger, "daily_report/clipboard", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([window](const auto& call, auto result) {
    if (call.method_name() != "write") { result->NotImplemented(); return; }
    const auto* args = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
    if (!args) { result->Error("ARGUMENTS", "Missing clipboard data"); return; }
    auto html_it = args->find(flutter::EncodableValue("html"));
    auto text_it = args->find(flutter::EncodableValue("text"));
    if (html_it == args->end() || text_it == args->end()) { result->Error("ARGUMENTS", "Missing clipboard formats"); return; }
    const auto* html = std::get_if<std::string>(&html_it->second);
    const auto* text = std::get_if<std::string>(&text_it->second);
    if (!html || !text) { result->Error("ARGUMENTS", "Invalid clipboard formats"); return; }
    const auto rich = ClipboardHtml(*html);
    const int count = MultiByteToWideChar(CP_UTF8, 0, text->c_str(), -1, nullptr, 0);
    if (!count) { result->Error("ENCODING", "Could not encode report"); return; }
    std::wstring plain(static_cast<size_t>(count), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, text->c_str(), -1, plain.data(), count);
    HGLOBAL rich_memory = ClipboardMemory(rich.c_str(), rich.size()+1);
    HGLOBAL plain_memory = ClipboardMemory(plain.data(), plain.size()*sizeof(wchar_t));
    const UINT html_format = RegisterClipboardFormatW(L"HTML Format");
    if (!rich_memory || !plain_memory || !html_format || !OpenClipboard(window)) {
      if (rich_memory) GlobalFree(rich_memory);
      if (plain_memory) GlobalFree(plain_memory);
      result->Error("CLIPBOARD", "Clipboard is busy. Try copying again."); return;
    }
    bool ok = EmptyClipboard() != 0;
    if (ok && SetClipboardData(CF_UNICODETEXT, plain_memory)) plain_memory = nullptr; else ok = false;
    if (ok && SetClipboardData(html_format, rich_memory)) rich_memory = nullptr; else ok = false;
    CloseClipboard();
    if (plain_memory) GlobalFree(plain_memory);
    if (rich_memory) GlobalFree(rich_memory);
    if (ok) result->Success(); else result->Error("CLIPBOARD", "Could not copy formatted report. Try again.");
  });
  return channel;
}
#endif
