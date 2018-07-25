/* --------------------------------------------------------------------------------- */
angular.module('matrix', []);
/* --------------------------------------------------------------------------------- */
angular.module('matrix').controller('matrix_controller', ['$scope', '$http', '$timeout', function ($scope, $http, $timeout) {
  $scope.radius_servers = [];
  $scope.realms = [];
  $scope.loading = true;
  init_tips($scope)
  get_data($scope, $http, $timeout);
}]);
/* --------------------------------------------------------------------------------- */
// get data, simple json data file is used
/* --------------------------------------------------------------------------------- */
function get_data($scope, $http, $timeout)
{
  $http({
    method  : 'GET',
    url     : '/matrix/data.json'
  })
  .then(function(response) {
    prepare_data($scope, response);
    graph_heat_map($scope);

    $timeout(function() {
      get_data($scope, $http, $timeout);
    }, 60000);
  });
}
/* --------------------------------------------------------------------------------- */
// prepare data for d3 graph
/* --------------------------------------------------------------------------------- */
function prepare_data($scope, response)
{
  var val;

  if($scope.radius_servers.length == 0) { // no radius servers, page was just displayed
    for(i in response.data) {
      if($scope.radius_servers.indexOf(response.data[i].host_name) == -1)
        $scope.radius_servers.push(response.data[i].host_name);

      if($scope.realms.indexOf(response.data[i].service_description) == -1)
        $scope.realms.push(response.data[i].service_description);
    }
  }

  if(!$scope.graph_data) {       // no graph data, page was just displayed
    $scope.graph_data = [];

    for(var i in response.data) {
      // if the last check was more than 4 hours ago, set it to unknown
      if(Number.isInteger(response.data[i].service_last_check) && response.data[i].service_last_check < (Math.floor(new Date().getTime() / 1000) - 14400))
        val = 3;        // unknown
      else
        val = response.data[i].service_state;

      $scope.graph_data.push({ row : $scope.radius_servers.indexOf(response.data[i].host_name),
                              col : $scope.realms.indexOf(response.data[i].service_description),
                              value : val });
    }

    for(var i in $scope.realms)
      $scope.realms[i] = $scope.realms[i].substring(1);     // remove "@"
  }

  else {
    for(var i in response.data) {
      // if the last check was more than 4 hours ago, set it to unknown
      if(Number.isInteger(response.data[i].service_last_check) && response.data[i].service_last_check < (Math.floor(new Date().getTime() / 1000) - 14400))
        val = 3;        // unknown
      else
        val = response.data[i].service_state;

      if($scope.graph_data[i].value != val)
        $scope.graph_data[i].value = val;         // assign new value
    }
  }
}
/* --------------------------------------------------------------------------------- */
// initialize tips
/* --------------------------------------------------------------------------------- */
function init_tips($scope)
{
  var svg = d3.select("body").append("svg");
  var colors = [ "#44bb77", "#ffaa44", "#ff5566", "#aa44ff" ];
  colors[99] = "#77aaff";

  var tip_arr = [
    { html : " <span style='color:" + colors[0]  + "'>", text : "OK" },
    { html : " <span style='color:" + colors[1]  + "'>", text : "WARNING" },
    { html : " <span style='color:" + colors[2]  + "'>", text : "CRITICAL" },
    { html : " <span style='color:" + colors[3]  + "'>", text : "UNKNOWN" },
  ]
  tip_arr[99] = { html : " <span style='color:" + colors[99] + "'>", text : "PENDING" };

  // row tooltip
  var row_tip = d3.tip()
    .attr('class', 'd3-tip')
    .offset([-10, 0])
    .html(function(d) {
    return "<strong>server:</strong> <span style='color:red'>" + d + "</span>";
  })

  svg.call(row_tip);

  // ==========================================================

  // col tooltip
  var col_tip = d3.tip()
    .attr('class', 'd3-tip')
    .offset(function(d) {
      return [ - this.getComputedTextLength() / 2 - 15, 10];
    })
    .html(function(d) {
    return "<strong>návštěvník z instituce:</strong> <span style='color:red'>" + d + "</span>";
  })

  svg.call(col_tip);

  // ==========================================================

  // cell tooltip
  var cell_tip = d3.tip()
    .attr('class', 'd3-tip')
    .offset([-10, 0])
    .html(function(d) {
      return "<text style='font-size:small;'>server:</text><strong> " + $scope.radius_servers[d.row] +
             ",</strong><text style='font-size:small;'> návštěvník z instituce: </text><strong>" + $scope.realms[d.col] + "</strong>," +
             tip_arr[d.value].html + tip_arr[d.value].text + "</span>";
  })

  svg.call(cell_tip);
  // ==========================================================

  $scope.svg = svg;
  $scope.row_tip = row_tip;
  $scope.col_tip = col_tip;
  $scope.cell_tip = cell_tip;
  $scope.svg_empty = true;
}
/* --------------------------------------------------------------------------------- */
// draw heat map graph
// based on http://bl.ocks.org/ianyfchang/8119685
/* --------------------------------------------------------------------------------- */
function graph_heat_map($scope)
{
  // ==========================================================
  // right margin for timestamp
  var margin = { top: 220, right: 250, bottom: 5, left: 230 };
  var cellSize = 18;

  var col_number = $scope.realms.length;
  var row_number = $scope.radius_servers.length;

  var width = cellSize * col_number;
  var height = cellSize * row_number;

  // ==========================================================
  var service_group_base = "https://ermon2.cesnet.cz/monitoring/list/servicegroups#!/monitoring/list/services?servicegroup_name=";
  var host_base = "https://ermon2.cesnet.cz/monitoring/list/hosts#!/monitoring/host/show?host="
  var service_base = "https://ermon2.cesnet.cz/monitoring/host/services?host=alpha.ujf.cas.cz#!/monitoring/service/show?host="
  // ==========================================================

  var rowLabel = $scope.radius_servers;
  var colLabel = $scope.realms;

  var hcrow = [];
  var hccol = [];

  for(var item in $scope.radius_servers)
    hcrow.push(Number(item));

  for(var item in $scope.realms)
    hccol.push(Number(item));

  // ==========================================================

  var data = $scope.graph_data;
  var t = d3.transition().duration(1500);
  
  // icingaweb2 colors
  var colors = [ "#44bb77", "#ffaa44", "#ff5566", "#aa44ff" ];
  colors[99] = "#77aaff";

  // ==========================================================

  var svg = $scope.svg;

  if(!$scope.svg_empty) {    // graph present
    d3.select(".map")
          .selectAll("rect")
          .data(data, function(d) { return d.row + ":" + d.col + ":" + d.value; })
          .transition(t)
          .style("fill", function(d) { return colors[d.value]; });
    return;
  }

  svg = svg.attr("width", width + margin.left + margin.right)
      .attr("height", height + margin.top + margin.bottom)
      .append("g")
      .attr("transform", "translate(" + margin.left + "," + margin.top + ")");

  // ==========================================================

  var rowLabels = svg.append("g")
      .selectAll(".rowLabelg")
      .data(rowLabel)
      .enter()
      .append("text")
      .text(function (d) { return d; })
      .attr("x", 0)
      .attr("y", function (d, i) { return hcrow.indexOf(i) * cellSize; })
      .style("text-anchor", "end")
      .attr("transform", "translate(-6," + cellSize + ")")
      .on('mouseover', $scope.row_tip.show)
      .on('mouseout', $scope.row_tip.hide)
      .on("click", function(d, i) { window.open(host_base + d); })
      .on("mousedown", function(d, i) { if(d3.event.button == 1) window.open(host_base + d); });

  // ==========================================================

  var colLabels = svg.append("g")
      .selectAll(".colLabelg")
      .data(colLabel)
      .enter()
      .append("text")
      .text(function (d) { return d; })
      .attr("x", 0)
      .attr("y", function (d, i) { return hccol.indexOf(i) * cellSize; })
      .style("text-anchor", "left")
      .attr("transform", "translate(" + cellSize  + ",-6) rotate (-90)")
      .on('mouseover', $scope.col_tip.show)
      .on('mouseout', $scope.col_tip.hide)
      .on("click", function(d, i) { window.open(service_group_base + d + "&limit=500"); })
      .on("mousedown", function(d, i) { if(d3.event.button == 1) window.open(service_group_base + d + "&limit=500"); });

  // ==========================================================

  var heatMap = svg.append("g").attr("class", "map")
      .selectAll("rect")
      .data(data, function(d) { return d.row + ":" + d.col + ":" + d.value; })
      .enter()
      .append("rect")
      .attr("x", function(d) { return (hccol.indexOf(d.col)) * cellSize + 6; })     // compensate for labels
      .attr("y", function(d) { return (hcrow.indexOf(d.row)) * cellSize + 4; })     // compensate for labels
      .attr("class", " clickable" )
      .attr("width", cellSize - 1)
      .attr("height", cellSize - 1)
      .style("fill", function(d) { return colors[d.value]; })
      .on('mouseover', $scope.cell_tip.show)
      .on('mouseout', $scope.cell_tip.hide)
      .on("click", function(d, i) { window.open(service_base + $scope.radius_servers[d.row] + "&service=%40" + $scope.realms[d.col]); })
      .on("mousedown", function(d, i) { if(d3.event.button == 1) window.open(service_base + $scope.radius_servers[d.row] + "&service=%40" + $scope.realms[d.col]); });

  // ==========================================================
  $scope.loading = false;
  $scope.svg_empty = false;
}
/* --------------------------------------------------------------------------------- */
