import 'package:flutter/material.dart';

/// A uniform-height list with a draggable fast-scroll handle on its right
/// edge, Samsung Music style: drag (or tap) the strip to jump anywhere in a
/// list of hundreds of rows, with a bubble showing [labelFor] of the row
/// currently at the top (an initial letter, a month, a duration...).
///
/// Every row gets [prototypeItem]'s height, which is what makes a drag
/// position map exactly onto a row index. The handle only appears once the
/// list has at least [minItemCount] rows and actually scrolls.
class FastScrollList extends StatefulWidget {
  const FastScrollList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.prototypeItem,
    required this.labelFor,
    this.minItemCount = 30,
  });

  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;
  final Widget prototypeItem;
  final String Function(int index) labelFor;
  final int minItemCount;

  @override
  State<FastScrollList> createState() => _FastScrollListState();
}

class _FastScrollListState extends State<FastScrollList> {
  static const double _handleHeight = 48;
  static const double _stripWidth = 28;

  final ScrollController _controller = ScrollController();
  bool _dragging = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Height of one row, derived from the laid-out scroll extent since every
  /// row shares the prototype's height.
  double _itemExtent(double bottomPadding) {
    final position = _controller.position;
    final content =
        position.maxScrollExtent + position.viewportDimension - bottomPadding;
    return widget.itemCount == 0 ? 0 : content / widget.itemCount;
  }

  void _jumpTo(double localY, double trackHeight, double bottomPadding) {
    if (!_controller.hasClients || widget.itemCount == 0) return;
    final usable = trackHeight - _handleHeight;
    final fraction = usable <= 0
        ? 0.0
        : ((localY - _handleHeight / 2) / usable).clamp(0.0, 1.0);
    final extent = _itemExtent(bottomPadding);
    final index = (fraction * (widget.itemCount - 1)).round();
    final max = _controller.position.maxScrollExtent;
    // Snap to a row boundary so the bubble's label is the row on top; the
    // very end still reaches the bottom of the list.
    final target = fraction >= 1.0 ? max : (index * extent).clamp(0.0, max);
    _controller.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final list = ListView.builder(
      controller: _controller,
      padding: EdgeInsets.only(bottom: bottomPadding),
      prototypeItem: widget.prototypeItem,
      itemCount: widget.itemCount,
      itemBuilder: widget.itemBuilder,
    );
    if (widget.itemCount < widget.minItemCount) return list;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackHeight = constraints.maxHeight - bottomPadding;
        return Stack(
          children: [
            // The handle needs laid-out scroll metrics, which only exist
            // after the first layout (and change when the list does).
            NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                if (mounted) setState(() {});
                return false;
              },
              child: list,
            ),
            Positioned(
              top: 0,
              right: 0,
              bottom: bottomPadding,
              width: _stripWidth + 120,
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  if (!_controller.hasClients ||
                      !_controller.position.hasContentDimensions ||
                      _controller.position.maxScrollExtent <= 0) {
                    return const SizedBox.shrink();
                  }
                  final position = _controller.position;
                  final fraction = (position.pixels / position.maxScrollExtent)
                      .clamp(0.0, 1.0);
                  final handleTop = fraction * (trackHeight - _handleHeight);
                  final extent = _itemExtent(bottomPadding);
                  final topIndex = extent <= 0
                      ? 0
                      : (position.pixels / extent)
                          .floor()
                          .clamp(0, widget.itemCount - 1);
                  return _buildHandle(
                      context, handleTop, topIndex, trackHeight, bottomPadding);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHandle(BuildContext context, double handleTop, int topIndex,
      double trackHeight, double bottomPadding) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (_dragging)
          Positioned(
            right: _stripWidth + 8,
            top: (handleTop - 8).clamp(0.0, trackHeight - 64),
            child: Material(
              color: scheme.primaryContainer,
              elevation: 4,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                constraints: const BoxConstraints(minWidth: 64, maxWidth: 112),
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                child: Text(
                  widget.labelFor(topIndex),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ),
          ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: _stripWidth,
          child: Semantics(
            label: 'Fast scroll',
            child: GestureDetector(
              key: const ValueKey('fastScrollHandle'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) =>
                  _jumpTo(d.localPosition.dy, trackHeight, bottomPadding),
              onVerticalDragStart: (d) {
                setState(() => _dragging = true);
                _jumpTo(d.localPosition.dy, trackHeight, bottomPadding);
              },
              onVerticalDragUpdate: (d) =>
                  _jumpTo(d.localPosition.dy, trackHeight, bottomPadding),
              onVerticalDragEnd: (_) => setState(() => _dragging = false),
              onVerticalDragCancel: () => setState(() => _dragging = false),
              child: Stack(
                children: [
                  Positioned(
                    top: handleTop,
                    right: 4,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: _dragging ? 10 : 6,
                      height: _handleHeight,
                      decoration: BoxDecoration(
                        color: _dragging
                            ? scheme.primary
                            : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
