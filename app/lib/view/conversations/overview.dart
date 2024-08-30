import 'package:flutter/material.dart';
import 'package:sph_plan/shared/exceptions/client_status_exceptions.dart';
import 'package:sph_plan/shared/types/conversations.dart';

import '../../client/client.dart';
import '../../client/fetcher.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../shared/widgets/error_view.dart';
import 'overview_dialogs.dart';
import 'chat.dart';

class ConversationsOverview extends StatefulWidget {
  const ConversationsOverview({super.key});

  @override
  State<StatefulWidget> createState() => _ConversationsOverviewState();
}

class _ConversationsOverviewState extends State<ConversationsOverview> {
  final ConversationsFetcher conversationsFetcher =
      client.fetchers.conversationsFetcher;

  final GlobalKey<RefreshIndicatorState> _refreshKey =
      GlobalKey<RefreshIndicatorState>();

  final ValueNotifier<bool> showHidden = ValueNotifier(false);

  @override
  void initState() {
    conversationsFetcher.fetchData();

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        bottom: const PreferredSize(
          preferredSize: Size(double.maxFinite, 18),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: SearchBar(
              autoFocus: false,
              hintText: "Titel, Lehrer, Datum, ...",
              trailing: [
                Padding(
                  padding: EdgeInsets.only(right: 12.0),
                  child: Icon(Icons.search),
                )
              ],
            ),
          ),
        ),
      ),
        body: StreamBuilder(
            stream: conversationsFetcher.stream,
            builder: (context, snapshot) {
              if (snapshot.data?.status == FetcherStatus.error) {
                return ErrorView(
                    error: snapshot.data!.error!,
                    name: AppLocalizations.of(context)!.messages,
                    retry: retryFetcher(conversationsFetcher));
              } else if (snapshot.data?.status == FetcherStatus.fetching || snapshot.data == null) {
                return const Center(child: CircularProgressIndicator());
              } else {
                return RefreshIndicator(
                  key: _refreshKey,
                  onRefresh: () async {
                    conversationsFetcher.fetchData(forceRefresh: true);
                  },
                  child: ListView.builder(
                      itemCount: snapshot.data?.content.length + 1,
                      itemBuilder: (context, index) {
                        if (index == snapshot.data?.content.length) {
                          return Padding(
                            padding: const EdgeInsets.only(left: 6.0, right: 6.0, top: 12.0, bottom: 16.0),
                            child: Column(
                              children: [
                                Text(
                                  AppLocalizations.of(context)!.noFurtherEntries,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                Text(
                                  AppLocalizations.of(context)!.notificationsNote,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          );
                        }

                        return ConversationTile(
                          entry: snapshot.data?.content[index]
                        );
                      }
                  ),
                );
              }
            }),
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ValueListenableBuilder(
              valueListenable: showHidden,
              builder: (context, show, _) {
                return FloatingActionButton(
                  heroTag: "visibility",
                  onPressed: () async {
                    showHidden.value = !showHidden.value;
                    client.conversations.showHidden = showHidden.value;
                    client.fetchers.conversationsFetcher.filter();
                  },
                  child: show ? const Icon(Icons.visibility) : const Icon(Icons.visibility_off),
                );
              }
            ),
            const SizedBox(height: 10,),
            FloatingActionButton(
              onPressed: () async {
                bool canChooseType;
                try {
                  canChooseType = await client.conversations.canChooseType();
                } on NoConnectionException {
                  return;
                }

                Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) {
                      if (canChooseType) {
                        return const TypeChooser();
                      }
                      return const CreateConversation(chatType: null);
                    })
                );
              },
              child: const Icon(Icons.edit),
            ),
          ],
        ));
  }
}

class ConversationTile extends StatefulWidget {
  final OverviewEntry entry;
  const ConversationTile({super.key, required this.entry});

  @override
  State<ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<ConversationTile> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Card(
              color: widget.entry.hidden
                  ? Theme.of(context).colorScheme.surfaceContainerLow.withOpacity(0.75)
                  : null,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ConversationsChat.fromEntry(widget.entry),
                    ),
                  );
                },
                customBorder: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (widget.entry.hidden) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 64.0),
                            child: Icon(
                              Icons.visibility_off,
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Theme.of(context).colorScheme.surfaceContainerHigh.withOpacity(0.25)
                                  : Theme.of(context).colorScheme.surfaceContainerLow.withOpacity(0.6),
                              size: 65,
                            ),
                          ),
                        ],
                      ),
                    ],
                    Badge(
                      smallSize: widget.entry.unread ? 9 : 0,
                      child: ListTile(
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              flex: 3,
                              child: Text(
                                widget.entry.title,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                widget.entry.shortName ?? "ERROR",
                                overflow: TextOverflow.ellipsis,
                                style: widget.entry.shortName != null
                                    ? Theme.of(context).textTheme.titleMedium
                                    : Theme.of(context).textTheme.titleMedium!.copyWith(color: Theme.of(context).colorScheme.error),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  widget.entry.date,
                                )
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


