import 'dart:async';
import 'dart:io';

import 'api_client.dart';

/// Turns whatever a service call threw into a message worth showing someone.
/// Deliberately does NOT guess a cause that isn't actually known — e.g. a
/// generic network failure during registration used to be shown as "that
/// username might already be taken", which was just wrong. If the backend
/// sent a real reason (`ApiException.message`), that's what's shown.
String describeError(Object error) {
  if (error is ApiException) {
    // The backend's own `detail` string — already human-readable
    // ("Username already taken", "Invalid username or password", ...).
    return error.message;
  }
  if (error is SocketException || error is TimeoutException) {
    return "couldn't reach the server — check it's running and reachable";
  }
  return "something went wrong — please try again";
}
