import 'package:flutter/widgets.dart';

class DropEventDetails {
  final Offset globalPosition;
  final Offset localPosition;
  DropEventDetails({required this.globalPosition, required this.localPosition});
}

class DropDoneDetails {
  final List<dynamic> files;
  final Offset globalPosition;
  final Offset localPosition;
  DropDoneDetails({required this.files, required this.globalPosition, required this.localPosition});
}

typedef DropEventHandler = void Function(DropEventDetails details);
typedef DropDoneHandler = void Function(DropDoneDetails details);

class DropTarget extends StatelessWidget {
  final Widget child;
  final DropEventHandler? onDragEntered;
  final DropEventHandler? onDragExited;
  final DropDoneHandler? onDragDone;

  const DropTarget({
    super.key,
    required this.child,
    this.onDragEntered,
    this.onDragExited,
    this.onDragDone,
  });

  @override
  Widget build(BuildContext context) => child;
}
