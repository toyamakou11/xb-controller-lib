#include <Windows.h>
extern "C" HRESULT __stdcall GameInputInitialize(REFIID, void** object) {
    *object = nullptr;
    return HRESULT_FROM_WIN32(ERROR_MOD_NOT_FOUND);
}
