/// Typed SMB exceptions raised by the SmbClient Dart wrapper.
library;

abstract class SmbException implements Exception {
  final String message;
  const SmbException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

class SmbAuthFailedException extends SmbException {
  const SmbAuthFailedException(super.message);
}

class SmbHostUnreachableException extends SmbException {
  const SmbHostUnreachableException(super.message);
}

class SmbShareNotFoundException extends SmbException {
  const SmbShareNotFoundException(super.message);
}

class SmbPathNotFoundException extends SmbException {
  const SmbPathNotFoundException(super.message);
}

class SmbAccessDeniedException extends SmbException {
  const SmbAccessDeniedException(super.message);
}

class SmbTimeoutException extends SmbException {
  const SmbTimeoutException(super.message);
}

class SmbUnknownException extends SmbException {
  const SmbUnknownException(super.message);
}

/// Maps a PlatformException error code (from Kotlin Result.error) to a typed
/// SmbException. Unknown codes fall back to SmbUnknownException.
SmbException smbExceptionFromCode(String? code, String? message) {
  final msg = message ?? 'unknown';
  switch (code) {
    case 'SMB_AUTH_FAILED':
      return SmbAuthFailedException(msg);
    case 'SMB_HOST_UNREACHABLE':
      return SmbHostUnreachableException(msg);
    case 'SMB_SHARE_NOT_FOUND':
      return SmbShareNotFoundException(msg);
    case 'SMB_PATH_NOT_FOUND':
      return SmbPathNotFoundException(msg);
    case 'SMB_ACCESS_DENIED':
      return SmbAccessDeniedException(msg);
    case 'SMB_TIMEOUT':
      return SmbTimeoutException(msg);
    default:
      return SmbUnknownException(msg);
  }
}
