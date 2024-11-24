import 'dart:io';

import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:sph_plan/applets/lessons/definition.dart';
import 'package:sph_plan/core/applet_parser.dart';
import 'package:sph_plan/models/lessons.dart';

import '../../../core/sph/sph.dart';
import '../../../shared/exceptions/client_status_exceptions.dart';

class LessonsStudentParser extends AppletParser<Lessons> {

  @override
  // TODO: implement validCacheDuration
  Duration? get validCacheDuration => lessonsDefinition.refreshInterval;

  @override
  Future<Lessons> getHome() async {
    var lessons = <Lesson>[];

    int unixTime = DateTime.now().millisecondsSinceEpoch;

    final response =
    await sph!.session.dio.get("https://start.schulportal.hessen.de/meinunterricht.php?cacheBreaker=$unixTime");
    var encryptedHTML = sph!.session.cryptor.decryptEncodedTags(response.data);
    var document = parse(encryptedHTML);

    var kursmappenDOM = document.getElementById("mappen");
    final _row = kursmappenDOM?.getElementsByClassName("row");
    var mappen = _row!.isEmpty ? null : _row[0].children;
    if (mappen != null) {
      for (var mappe in mappen) {
        String url = mappe.querySelector("a.btn.btn-primary")!.attributes["href"]!;
        lessons.add(Lesson(
          name: mappe.getElementsByTagName("h2")[0].text.trim(),
          teacher: mappe.querySelector("div.btn-group>button")?.attributes["title"],
          courseURL: Uri.parse(url),
          courseID: url.split("id=")[1],
        ));
      }
    }

    //Aktuelle Einträge
    var schoolClasses = document.querySelectorAll("tr.printable");
    for (var schoolClass in schoolClasses) {
      var teacher = schoolClass.querySelector(".teacher");

      if (schoolClass.querySelector(".datum") != null) {
        String? topicTitle = schoolClass.querySelector(".thema")?.text.trim();
        String? teacherKuerzel = teacher
            ?.getElementsByClassName("btn btn-primary dropdown-toggle btn-xs")[0]
            .text
            .trim();
        String? teacherName = teacher?.querySelector("ul>li>a>i.fa")?.parent?.text.trim();
        String? topicDateString = schoolClass.querySelector(".datum")?.text.trim();
        DateTime? topicDate = DateTime.parse(topicDateString!.split(".").reversed.join("-"));
        String? courseURL = schoolClass.querySelector("td>h3>a")?.attributes["href"];
        int fileCount = schoolClass.getElementsByClassName('file').length;

        Homework? homework;
        if (schoolClass.querySelector('.homework') != null) {
          homework = Homework(
            description: schoolClass.querySelector('.realHomework')!.text.trim(),
            homeWorkDone: schoolClass.querySelector('.undone') == null,
          );
        }
        String entryID = schoolClass.attributes["data-entry"]!;

        // find lesson by courseURL and add currentEntry
        for (var lesson in lessons) {
          if (lesson.courseURL.toString() == courseURL) {
            lesson.currentEntry = CurrentEntry(
              entryID: entryID,
              topicTitle: topicTitle,
              topicDate: topicDate,
              homework: homework,
              uploads: const [],
              files: List.generate(fileCount, (_)=>LessonsFile()),
            );
            lesson.teacher = teacherName;
            lesson.teacherKuerzel = teacherKuerzel;
            break;
          }
        }
      }
    }

    //Anwesenheiten
    var anwesendDOM = document.getElementById("anwesend");
    var thead = anwesendDOM?.querySelector("thead>tr");
    var tbody = anwesendDOM?.querySelectorAll("tbody>tr");

    List<String> keys = [];
    thead?.children.forEach((element) => keys.add(element.text.trim()));

    tbody?.forEach((row) {
      var textElements = [];
      for (var i = 0; i < row.children.length; i++) {
        var col = row.children[i];
        col.querySelector("div.hidden.hidden_encoded")?.innerHtml = "";

        textElements.add(col.text.trim());
      }

      Map<String, String> attendances = {};

      for (int i = 0; i < keys.length; i++) {
        var key = keys[i].toLowerCase();
        var value = textElements[i];
        if (['kurs', 'lehrkraft'].contains(key)) continue;

        if (value == "") {
          value = "0";
        }

        attendances[key] = value;
      }
      var hyperlinkToCourse = row.getElementsByTagName("a")[0];
      String courseURL = hyperlinkToCourse.attributes["href"]!;

      // find lesson by courseURL and add attendances
      for (var lesson in lessons) {
        if (courseURL.contains(lesson.courseID)) {
          lesson.attendances = attendances;
          break;
        }
      }
    });

    //sort lessons by date
    lessons.sort((a, b) {
      if (a.currentEntry?.topicDate == null || b.currentEntry?.topicDate == null) {
        return 0;
      }
      return b.currentEntry!.topicDate!.compareTo(a.currentEntry!.topicDate!);
    });

    return lessons;
  }

  Future<DetailedLesson> getDetailedCourseView(String url) async {
    try {
      String courseID = url.split("id=")[1];

      final response =
      await sph!.session.dio.get("https://start.schulportal.hessen.de/$url");
      final String decryptedHTML = sph!.session.cryptor.decryptEncodedTags(response.data);
      Document document = parse(decryptedHTML);

      //course name
      var heading = document.getElementById("content")?.querySelector("h1");
      heading?.children[0].innerHtml = "";
      String? courseTitle = heading?.text.trim();

      Uri? semester1URL;
      //halbjahr2
      var halbJahrButtons =
      document.getElementsByClassName("btn btn-default hidden-print");
      if (halbJahrButtons.length > 1) {
        if (halbJahrButtons[0].attributes["href"]!.contains("&halb=1")) {
          semester1URL = Uri.parse(halbJahrButtons[0].attributes["href"]!);
        }
      }

      //historie
      List<CurrentEntry> history = [];

      Element? historySection = document.getElementById("history");
      List<Element>? historyTableRows = historySection?.querySelectorAll("table>tbody>tr");

      historyTableRows?.forEach((tableRow) {
        tableRow.children[2]
            .querySelector("div.hidden.hidden_encoded")
            ?.innerHtml = "";

        String? description = tableRow.children[1]
            .querySelector("span.markup i.far.fa-comment-alt:first-child")
            ?.parent
            ?.text
            .trim();

        String? homework = tableRow.children[1]
            .querySelector("span.homework + br + span.markup")
            ?.text
            .trim();
        bool homeworkDone = tableRow.querySelectorAll("span.done.hidden").isEmpty;


        List<LessonsFile> files = [];
        if (tableRow.children[1].querySelector("div.alert.alert-info") !=
            null) {
          String baseURL = "https://start.schulportal.hessen.de/";
          baseURL += tableRow.children[1]
              .querySelector("div.alert.alert-info>a")!
              .attributes["href"]!;
          baseURL = baseURL.replaceAll("&b=zip", "");

          for (var fileDiv in tableRow.getElementsByClassName("files")[0].children) {
            String? filename = fileDiv.attributes["data-file"];
            files.add(LessonsFile(
              fileName: filename,
              fileSize: fileDiv
                  .querySelector("a>small")
                  ?.text,
              fileURL: Uri.parse("$baseURL&f=$filename"),
            ));
          }
        }

        List<LessonUpload> uploads = [];
        final uploadGroups =
        tableRow.children[1].querySelectorAll("div.btn-group");
        for (final uploadGroup in uploadGroups) {
          final openUpload = uploadGroup.querySelector(".btn-warning");
          final closedUpload = uploadGroup.querySelector(".btn-default");

          const String baseURL = "https://start.schulportal.hessen.de/";

          if (openUpload != null) {
            uploads.add(LessonUpload(
              name: openUpload.nodes[2].text!.trim(),
              status: "open",
              url: Uri.parse(baseURL+uploadGroup.querySelector("ul.dropdown-menu li a")!.attributes["href"]!),
              uploaded: openUpload.querySelector("span.badge")?.text,
              date: openUpload.querySelector("small")?.text
                  .replaceAll("\n", "")
                  .replaceAll("                                                                ", "")
                  .replaceAll("bis ", "")
                  .replaceAll("um", ""),
            ));
          } else if (closedUpload != null) {
            uploads.add(LessonUpload(
              name: closedUpload.nodes[2].text!.trim(),
              status: "closed",
              url: Uri.parse(baseURL+uploadGroup.querySelector("ul.dropdown-menu li a")!.attributes["href"]!),
              uploaded: closedUpload.querySelector("span.badge")?.text,
            ));
          }
        }

        List<String> dateInformation = tableRow.children[0].text.split("\n").map((e) => e.trim()).where((element) => element!="").toList();

        history.add(CurrentEntry(
          entryID: tableRow.attributes["data-entry"]!,
          topicTitle: tableRow.children[1].querySelector("big>b")?.text.trim(),
          description: description,
          presence: tableRow.children[2].text.trim() == 'nicht erfasst' ? null : tableRow.children[2].text.trim(),
          topicDate: DateTime.parse(dateInformation[0].split(".").reversed.join("-")),
          schoolHours: dateInformation[1].replaceAll("Stunde", "").trimRight(),
          files: files,
          uploads: uploads,
          homework: (homework != null) ? Homework(description: homework, homeWorkDone: homeworkDone) : null,
        ));
      });

      //anwesenheiten
      Element? presenceSection = document.getElementById("attendanceTable");
      List<Element>? attendanceTableRows = presenceSection?.querySelectorAll("table>tbody>tr");

      Map<String, String> attendances = {};

      attendanceTableRows?.forEach((row) {
        var encodedElements = row.getElementsByClassName("hidden_encoded");
        for (var e in encodedElements) {
          e.innerHtml = "";
        }
        attendances[row.children[0].text.trim()] = row.children[1].text.trim();
      });

      //leistungen
      var marksSection = document.getElementById("marks");
      List markTableRows =
      marksSection?.querySelectorAll("table>tbody>tr") as List;

      List<LessonMark> marks = [];

      for (var row in markTableRows) {
        var encodedElements = row.getElementsByClassName("hidden_encoded");
        for (var e in encodedElements) {
          e.innerHtml = "";
        }

        if (row.children.length == 3) {
          marks.add(LessonMark(
            name: row.children[0].text.trim(),
            date: row.children[1].text.trim(),
            mark: row.children[2].text.trim(),
            comment: (row.children.length == 2)
                ? row.children[1].text.trim().split(":").sublist(1).join(":")
                : null,
          ));
        }
      }

      //leistungskontrollen
      Element? examSection = document.getElementById("klausuren");

      List<LessonExam> lessonExams = [];

      if (!(examSection?.children)![0].text.contains("Diese Kursmappe beinhaltet leider noch keine Leistungskontrollen!")) {

        for (var element in examSection?.children ?? []) {
          String exams = "";

          final elements = element.querySelectorAll("ul li");

          for (var element in elements) {
            //todo better solution that splitting the string with "  ...  "
            var exam = element.text.trim().split(
                "                                                                                                    ");
            exams +=
            "${exam.first.trim()} ${exam.last != exam.first ? exam.last.trim() : ""}";
            if (element != elements.last) {
              exams += "\n";
            }
          }

          lessonExams.add(LessonExam(
            name: element.querySelector("h1,h2,h3,h4,h5,h6")?.text.trim() ?? "",
            value: exams == "" ? "Keine Daten!" : exams,
          ));
        }
      }
      Element teacherButton = document.getElementsByClassName("btn btn-primary dropdown-toggle btn-md")[0];
      return DetailedLesson(
        courseID: courseID,
        name: courseTitle!,
        teacher: teacherButton.parent!.querySelector(".dropdown-menu")!.text.trim(),
        teacherKuerzel: teacherButton.text.trim(),
        history: history,
        marks: marks,
        exams: lessonExams,
        attendances: attendances,
        semester1URL: semester1URL,
      );
    } catch (e) {
      throw UnknownException();
    }
  }

  Future<String> setHomework(
      String courseID, String courseEntry, bool status) async {
    //returns the response of the http request. 1 means success.

    final response = await sph!.session.dio.post(
      "https://start.schulportal.hessen.de/meinunterricht.php",
      data: {
        "a": "sus_homeworkDone",
        "entry": courseEntry,
        "id": courseID,
        "b": status ? "done" : "undone"
      },
      options: Options(
        headers: {
          "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
          "X-Requested-With": "XMLHttpRequest", //this is important
        },
      ),
    );

    return response.data;
  }

  Future<String> deleteUploadedFile(
      {required String course,
        required String entry,
        required String upload,
        required String file,
        required String userPasswordEncrypted}) async {
    try {
      final response = await sph!.session.dio.post(
          "https://start.schulportal.hessen.de/meinunterricht.php",
          data: {
            "a": "sus_abgabe",
            "d": "delete",
            "b": course,
            "e": entry,
            "id": upload,
            "f": file,
            "pw": userPasswordEncrypted
          },
          options: Options(
            headers: {
              "Accept": "*/*",
              "Content-Type":
              "application/x-www-form-urlencoded; charset=UTF-8",
              "Sec-Fetch-Dest": "empty",
              "Sec-Fetch-Mode": "cors",
              "Sec-Fetch-Site": "same-origin",
              "X-Requested-With": "XMLHttpRequest",
            },
          ));

      // "-1" Wrong password
      // "-2" Delete was not possible
      // "0" Unknown error
      // "1" Lanis had a good day
      return response.data;
    } on (SocketException, DioException) {
      throw NetworkException();
    } catch (e) {
      throw UnknownException();
    }
  }

  Future<dynamic> getUploadInfo(String url) async {
    try {
      final response = await sph!.session.dio.get(url);
      final parsed = parse(response.data);

      final requirementsGroup =
      parsed.querySelectorAll("div#content div.row div.col-md-12")[1];

      final String? start = requirementsGroup
          .querySelector("span.editable")
          ?.text
          .trim()
          .replaceAll(" ab", "");
      final String? deadline = requirementsGroup
          .querySelector("b span.editable")
          ?.text
          .trim()
          .replaceAll("  spätestens", "");
      final bool uploadMultipleFiles = requirementsGroup
          .querySelectorAll(
          "i.fa.fa-check-square-o.fa-fw + span.label.label-success")[0]
          .text
          .trim() ==
          "erlaubt"
          ? true
          : false;
      final bool uploadAnyNumberOfTimes = requirementsGroup
          .querySelectorAll(
          "i.fa.fa-check-square-o.fa-fw + span.label.label-success")[1]
          .text
          .trim() ==
          "erlaubt"
          ? true
          : false;
      final String? visibility = requirementsGroup
          .querySelector("i.fa.fa-eye.fa-fw + span.label")
          ?.text
          .trim() ??
          requirementsGroup
              .querySelector("i.fa.fa-eye-slash.fa-fw + span.label")
              ?.text
              .trim();
      final String? automaticDeletion = requirementsGroup
          .querySelector("i.fa.fa-trash-o.fa-fw + span.label.label-info")
          ?.text
          .trim();
      final List<String> allowedFileTypes = requirementsGroup
          .querySelectorAll("i.fa.fa-file.fa-fw + span.label.label-warning")[0]
          .text
          .trim()
          .split(", ");
      final String maxFileSize = requirementsGroup
          .querySelectorAll("i.fa.fa-file.fa-fw + span.label.label-warning")[1]
          .text
          .trim();
      final String? additionalText = requirementsGroup
          .querySelector("div.alert.alert-info")
          ?.text
          .split("\n")[1]
          .trim();

      final ownFilesGroup =
      parsed.querySelectorAll("div#content div.row div.col-md-12")[2];
      final List<OwnFile> ownFiles = [];
      for (final group in ownFilesGroup.querySelectorAll("ul li")) {
        final fileIndex = RegExp(r"f=(\d+)");

        ownFiles.add(OwnFile(
            name: group.querySelector("a")!.text.trim(),
            url:
            "https://start.schulportal.hessen.de/${group.querySelector("a")!.attributes["href"]!}",
            time: group.querySelector("small")!.text,
            index: fileIndex
                .firstMatch(group.querySelector("a")!.attributes["href"]!)!
                .group(1)!,
            comment: group.nodes.elementAtOrNull(10) != null
                ? group.nodes[10].text!.trim()
                : null));
      }

      final uploadForm = parsed.querySelector("div.col-md-7 form");
      String? courseId;
      String? entryId;
      String? uploadId;

      if (uploadForm != null) {
        courseId =
        uploadForm.querySelector("input[name='b']")!.attributes["value"]!;
        entryId =
        uploadForm.querySelector("input[name='e']")!.attributes["value"]!;
        uploadId =
        uploadForm.querySelector("input[name='id']")!.attributes["value"]!;
      }

      final publicFilesGroup =
      parsed.querySelector("div#content div.row div.col-md-5");
      final List<PublicFile> publicFiles = [];

      if (publicFilesGroup != null) {
        for (final group in publicFilesGroup.querySelectorAll("ul li")) {
          final fileIndex = RegExp(r"f=(\d+)");

          publicFiles.add(PublicFile(
            name: group.querySelector("a")!.text.trim(),
            url:
            "https://start.schulportal.hessen.de/${group.querySelector("a")!.attributes["href"]!}",
            person: group.querySelector("span.label.label-info")!.text.trim(),
            index: fileIndex
                .firstMatch(group.querySelector("a")!.attributes["href"]!)!
                .group(1)!,
          ));
        }
      }

      return {
        "start": start,
        "deadline": deadline,
        "upload_multiple_files": uploadMultipleFiles,
        "upload_any_number_of_times": uploadAnyNumberOfTimes,
        "visibility": visibility,
        "automatic_deletion": automaticDeletion,
        "allowed_file_types": allowedFileTypes,
        "max_file_size": maxFileSize,
        "course_id": courseId,
        "entry_id": entryId,
        "upload_id": uploadId,
        "own_files": ownFiles,
        "public_files": publicFiles,
        "additional_text": additionalText,
      };
    } on (SocketException, DioException) {
      throw NetworkException();
    } catch (e) {
      throw UnknownException();
    }
  }

  Future<List<FileStatus>> uploadFile({
    required String course,
    required String entry,
    required String upload,
    required MultipartFile file1,
    MultipartFile? file2,
    MultipartFile? file3,
    MultipartFile? file4,
    MultipartFile? file5,
  }) async {
    try {
      final FormData uploadData = FormData.fromMap({
        "a": "sus_abgabe",
        "b": course,
        "e": entry,
        "id": upload,
        "file1": file1,
        "file2": file2,
        "file3": file3,
        "file4": file4,
        "file5": file5
      });

      final response = await sph!.session.dio.post(
          "https://start.schulportal.hessen.de/meinunterricht.php",
          data: uploadData,
          options: Options(headers: {
            "Accept": "*/*",
            "Content-Type": "multipart/form-data;",
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": "same-origin",
          }));

      final parsed = parse(response.data);

      final statusMessagesGroup =
      parsed.querySelectorAll("div#content div.col-md-12")[2];

      final List<FileStatus> statusMessages = [];
      for (final statusMessage
      in statusMessagesGroup.querySelectorAll("ul li")) {
        statusMessages.add(FileStatus(
          name: statusMessage.querySelector("b")!.text.trim(),
          status: statusMessage.querySelector("span.label")!.text.trim(),
          message: statusMessage.nodes[4].text?.trim(),
        ));
      }

      return statusMessages;
    } on (SocketException, DioException) {
      throw NetworkException();
    } catch (e) {
      throw UnknownException();
    }
  }
}