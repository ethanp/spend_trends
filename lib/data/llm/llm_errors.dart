class LlmException(final String message) implements Exception {
  @override
  String toString() => message;
}

class RateLimitedException() extends LlmException {
  this : super('LLM rate limited. Try again later.');
}
