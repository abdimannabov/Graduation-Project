function formatContext(context) {
  if (!context) return '';
  try {
    return ` ${JSON.stringify(context)}`;
  } catch (err) {
    return ' {"logContext":"unserializable"}';
  }
}

function log(level, message, context) {
  const timestamp = new Date().toISOString();
  const line = `[${timestamp}] [${level}] ${message}${formatContext(context)}`;

  if (level === 'ERROR') {
    console.error(line);
    return;
  }

  console.log(line);
}

function info(message, context) {
  log('INFO', message, context);
}

function warn(message, context) {
  log('WARN', message, context);
}

function error(message, context) {
  log('ERROR', message, context);
}

module.exports = {
  info,
  warn,
  error,
};
