function vote(dir, id) {
  if (!(dir == "up" || dir == "down")) {
    alert("wtf?");
    return
  }

  path = "/vote/" + dir + "/" + id + "?format=json";
  arrow = "#i" + id;
  score = "#i" + id + "score";

  $.ajax({
    url: path,
    success: function(data, stat, xhr) {
      if (data.success) {
        $(score).text(data.score);
        $(arrow + "up").removeClass("upvote");
        $(arrow + "down").removeClass("downvote");
        if (data.state != "clear") {
          $(arrow + data.state).addClass(data.state + "vote");
        }
      } else {
        alert("App Error: " + data.error);
      }
    },
    error: function(xhr, stat, error) {
      alert("Other Error: " + error + " (" + stat + ")");
    }
  });
}
