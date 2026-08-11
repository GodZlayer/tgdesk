#include "tgdesk_log.h"

#include <windows.h>

#include <cstdio>
#include <fstream>
#include <mutex>

namespace {

constexpr const char kLogDir[] = "C:\\ProgramData\\TGDesk\\logs";
constexpr const char kLogPath[] = "C:\\ProgramData\\TGDesk\\logs\\tgdesk-diag.log";
constexpr const char kSwitchPath[] = "C:\\ProgramData\\TGDesk\\logs\\debug.on";

// Teto do arquivo. Uma sessão instrumentada gera muita linha por segundo
// durante um redimensionamento, e o disco do cliente não é nosso para encher:
// ao estourar, o arquivo recomeça. Quem investiga quer o que acabou de
// acontecer, não o que aconteceu há três dias.
constexpr std::streamoff kMaxBytes = 8 * 1024 * 1024;

std::mutex& LogMutex() {
  static std::mutex mutex;
  return mutex;
}

bool FileExists(const char* path) {
  const DWORD attributes = ::GetFileAttributesA(path);
  return attributes != INVALID_FILE_ATTRIBUTES &&
         !(attributes & FILE_ATTRIBUTE_DIRECTORY);
}

std::string Timestamp() {
  SYSTEMTIME now = {};
  ::GetLocalTime(&now);
  char buffer[32];
  std::snprintf(buffer, sizeof(buffer), "%02d:%02d:%02d.%03d", now.wHour,
                now.wMinute, now.wSecond, now.wMilliseconds);
  return std::string(buffer);
}

}  // namespace

bool TgdeskLogEnabled() {
  // Resolvida uma vez e guardada: ver o comentário do cabeçalho.
  static const bool enabled = [] {
    char value[8] = {0};
    const DWORD length =
        ::GetEnvironmentVariableA("TGDESK_DEBUG_LOG", value, sizeof(value));
    if (length > 0 && length < sizeof(value) && value[0] == '1') {
      return true;
    }
    return FileExists(kSwitchPath);
  }();
  return enabled;
}

void TgdeskLog(const char* area, const std::string& message) {
  if (!TgdeskLogEnabled()) {
    return;
  }

  std::lock_guard<std::mutex> guard(LogMutex());
  ::CreateDirectoryA(kLogDir, nullptr);

  // O TGDesk roda vários processos ao mesmo tempo (serviço, sessão, cm,
  // bandeja) e todos escrevem aqui. Sem o pid, duas linhas vizinhas podem vir
  // de processos diferentes e a leitura induz a erro.
  std::ofstream file(kLogPath, std::ios::app);
  if (!file.is_open()) {
    return;
  }
  if (file.tellp() > kMaxBytes) {
    file.close();
    file.open(kLogPath, std::ios::trunc);
    if (!file.is_open()) {
      return;
    }
  }
  file << Timestamp() << " [" << ::GetCurrentProcessId() << ":"
       << ::GetCurrentThreadId() << "] " << area << ": " << message
       << std::endl;
}
