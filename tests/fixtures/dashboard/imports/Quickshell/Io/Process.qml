import QtQuick
Item { property var command; property bool running: false; property var stdout; property var stderr; property var environment; signal exited(int code, int status); signal started() }
