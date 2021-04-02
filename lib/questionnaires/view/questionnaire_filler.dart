import 'package:fhir/r4/r4.dart';
import 'package:flutter/material.dart';

import '../../logging/logging.dart';
import '../../resource_provider/resource_provider.dart';
import '../questionnaires.dart';

class QuestionnaireFiller extends StatefulWidget {
  final WidgetBuilder builder;
  final ExternalResourceProvider questionnaireProvider;
  final ExternalResourceProvider? questionnaireResponseProvider;

  final ExternalResourceProvider? externalResourceProvider;
  static final logger = Logger(QuestionnaireFiller);

  Future<QuestionnaireTopLocation> _createTopLocation() async {
    await questionnaireProvider.init();
    final questionnaire = ArgumentError.checkNotNull(
        questionnaireProvider.getResource((Questionnaire).toString())
            as Questionnaire?,
        "'Questionnaire' asset");
    final topLocation = QuestionnaireTopLocation.fromQuestionnaire(
        questionnaire,
        // TODO: Make this a parameter with a default
        aggregators: [
          TotalScoreAggregator(),
          NarrativeAggregator(),
          QuestionnaireResponseAggregator()
        ],
        externalResourceProvider: externalResourceProvider);

    await Future.wait([
      topLocation.initState(),
      if (questionnaireResponseProvider != null)
        questionnaireResponseProvider!.init()
    ]);

    final response = questionnaireResponseProvider?.getResource(
        (QuestionnaireResponse).toString()) as QuestionnaireResponse?;
    topLocation.populate(response);

    return topLocation;
  }

  const QuestionnaireFiller(this.questionnaireProvider,
      {Key? key,
      required this.builder,
      this.externalResourceProvider,
      this.questionnaireResponseProvider})
      : super(key: key);

  static QuestionnaireFillerData of(BuildContext context) {
    final result =
        context.dependOnInheritedWidgetOfExactType<QuestionnaireFillerData>();
    assert(result != null, 'No QuestionnaireFillerData found in context');
    return result!;
  }

  @override
  _QuestionnaireFillerState createState() => _QuestionnaireFillerState();
}

class _QuestionnaireFillerState extends State<QuestionnaireFiller> {
  static final logger = Logger(_QuestionnaireFillerState);

  late final Future<QuestionnaireTopLocation> builderFuture;
  QuestionnaireTopLocation? _topLocation;
  void Function()? _onTopChangeListenerFunction;

  @override
  void initState() {
    super.initState();
    builderFuture = widget._createTopLocation();
  }

  @override
  void dispose() {
    logger.log('dispose', level: LogLevel.trace);

    if (_onTopChangeListenerFunction != null && _topLocation != null) {
      _topLocation!.removeListener(_onTopChangeListenerFunction!);
      _topLocation = null;
      _onTopChangeListenerFunction = null;
    }
    super.dispose();
  }

  void _onTopChange() {
    logger.log('_onTopChange', level: LogLevel.trace);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    logger.log('Enter build()', level: LogLevel.trace);
    return FutureBuilder<QuestionnaireTopLocation>(
        future: builderFuture,
        builder: (context, snapshot) {
          switch (snapshot.connectionState) {
            case ConnectionState.active:
              // This should never happen in our use-case (is for streaming)
              logger.log('FutureBuilder is active...', level: LogLevel.warn);
              return QuestionnaireLoadingIndicator(snapshot);
            case ConnectionState.none:
              return QuestionnaireLoadingIndicator(snapshot);
            case ConnectionState.waiting:
              logger.log('FutureBuilder still waiting for data...',
                  level: LogLevel.debug);
              return QuestionnaireLoadingIndicator(snapshot);
            case ConnectionState.done:
              if (snapshot.hasError) {
                logger.log('FutureBuilder hasError', level: LogLevel.warn);
                return QuestionnaireLoadingIndicator(snapshot);
              }
              if (snapshot.hasData) {
                logger.log('FutureBuilder hasData');
                _topLocation = snapshot.data;
                // TODO: There has got to be a more elegant way! Goal is to register the lister exactly once, after the future has completed.
                // Can I do .then for that?
                if (_onTopChangeListenerFunction == null) {
                  _onTopChangeListenerFunction = () => _onTopChange();
                  _topLocation!.addListener(_onTopChangeListenerFunction!);
                }
                return QuestionnaireFillerData._(
                  _topLocation!,
                  builder: widget.builder,
                );
              }
              throw StateError(
                  'FutureBuilder snapshot has unexpected state: $snapshot');
          }
        });
  }
}

class QuestionnaireFillerData extends InheritedWidget {
  static final logger = Logger(QuestionnaireFillerData);
  final QuestionnaireTopLocation topLocation;
  final Iterable<QuestionnaireLocation> surveyLocations;
  late final List<QuestionnaireItemFiller?> _itemFillers;
  late final int _revision;

  QuestionnaireFillerData._(
    this.topLocation, {
    Key? key,
    required WidgetBuilder builder,
  })   : _revision = topLocation.revision,
        surveyLocations = topLocation.preOrder(),
        _itemFillers = List<QuestionnaireItemFiller?>.filled(
            topLocation.preOrder().length, null),
        super(key: key, child: Builder(builder: builder));

  T aggregator<T extends Aggregator>() {
    return topLocation.aggregator<T>();
  }

  static QuestionnaireFillerData of(BuildContext context) {
    final result =
        context.dependOnInheritedWidgetOfExactType<QuestionnaireFillerData>();
    assert(result != null, 'No QuestionnaireFillerData found in context');
    return result!;
  }

  List<QuestionnaireItemFiller> itemFillers() {
    for (int i = 0; i < _itemFillers.length; i++) {
      if (_itemFillers[i] == null) {
        _itemFillers[i] = itemFillerAt(i);
      }
    }

    return _itemFillers
        .map<QuestionnaireItemFiller>(
            (itemFiller) => ArgumentError.checkNotNull(itemFiller))
        .toList();
  }

  QuestionnaireItemFiller itemFillerAt(int index) {
    _itemFillers[index] ??= QuestionnaireItemFiller.fromQuestionnaireItem(
        surveyLocations.elementAt(index));

    return _itemFillers[index]!;
  }

  @override
  bool updateShouldNotify(QuestionnaireFillerData oldWidget) {
    return oldWidget._revision != _revision;
  }
}