/* --------------------------------------------------------------------------------- */
angular.module('matrix', []);
/* --------------------------------------------------------------------------------- */
// global variables
/* --------------------------------------------------------------------------------- */
// size of map cell
var cellSize = 18;
// icingaweb2 colors
var colors = [ "#44bb77", "#ffaa44", "#ff5566", "#aa44ff" ];
colors[99] = "#77aaff";
/* --------------------------------------------------------------------------------- */
angular.module('matrix').controller('matrix_controller', ['$scope', '$http', '$timeout', function ($scope, $http, $timeout) {
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
// create new graph_data
/* --------------------------------------------------------------------------------- */
function create_graph_data($scope, response)
{
  var val;
  var soft;

  $scope.graph_data = [];
  $scope.radius_servers = [];
  $scope.realms = [];
  $scope.total_health = { 0  : 0,
                          1  : 0,
                          2  : 0,
                          3  : 0,
                          99 : 0 };

  for(var i in response.data) {
    if($scope.radius_servers.indexOf(response.data[i].host_name) == -1)
      $scope.radius_servers.push(response.data[i].host_name);

    if($scope.realms.indexOf(response.data[i].service_description) == -1)
      $scope.realms.push(response.data[i].service_description);

    soft = 0;

    // if the last check was more than 4 hours ago, set it to unknown
    if(Number.isInteger(response.data[i].service_last_check) && response.data[i].service_last_check < (Math.floor(new Date().getTime() / 1000) - 14400))
      val = 3;        // unknown
    else {
      if(response.data[i].service_state_type == 0 && response.data[i].service_state != 99) {       // soft state and not PENDING
        soft = response.data[i].service_state;
        val = 0;        // set state to OK, current state is NOT ok, but only in soft state
      }
      else                                                // hard state
        val = response.data[i].service_state;
    }

    $scope.total_health[val]++;

    $scope.graph_data.push({ row : $scope.radius_servers.indexOf(response.data[i].host_name),
                            col : $scope.realms.indexOf(response.data[i].service_description),
                            value : val,
                            soft : soft });
  }

  for(var i in $scope.realms)
    $scope.realms[i] = $scope.realms[i].substring(1);     // remove "@"

  $scope.last_data_len = response.data.length;
}
/* --------------------------------------------------------------------------------- */
// update graph data
/* --------------------------------------------------------------------------------- */
function update_graph_data($scope, response)
{
  var val;
  var soft;

  for(var i in response.data) {
    // if the last check was more than 4 hours ago, set it to unknown
    if(Number.isInteger(response.data[i].service_last_check) && response.data[i].service_last_check < (Math.floor(new Date().getTime() / 1000) - 14400))
      val = 3;        // unknown
    else {
      if(response.data[i].service_state_type == 0 && response.data[i].service_state != 99) {       // soft state and not PENDING
        soft = response.data[i].service_state;
        val = 0;        // set state to OK, current state is NOT ok, but only in soft state
      }
      else                                                // hard state
        val = response.data[i].service_state;
    }

    if($scope.graph_data[i].value != val) {
      $scope.total_health[$scope.graph_data[i].value]--;    // decrement old value
      $scope.graph_data[i].value = val;         // assign new value
      $scope.total_health[val]++;                           // increment new value
    }
  }
}
/* --------------------------------------------------------------------------------- */
// prepare data for d3 graph
/* --------------------------------------------------------------------------------- */
function prepare_data($scope, response)
{
  if(!$scope.graph_data) {       // no graph data, page was just displayed
    create_graph_data($scope, response);
  }
  else {
    if($scope.last_data_len != response.data.length) {   // servers or realms were added or removed
      location.reload();        // reload the page
    }
    else
      update_graph_data($scope, response);
  }
}
/* --------------------------------------------------------------------------------- */
// initialize tips
/* --------------------------------------------------------------------------------- */
function init_tips($scope)
{
  var svg = d3.select("body").append("svg");
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
      return "<text style='font-weight:normal;'>server:</text><strong> " + $scope.radius_servers[d.row] +
             ",</strong><text style='font-weight:normal;'> návštěvník z instituce: </text><strong>" + $scope.realms[d.col] + "</strong>," +
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
  var margin = { top: 220, right: 250, bottom: 240, left: 280 };

  var col_number = $scope.realms.length;
  var row_number = $scope.radius_servers.length;

  var width = cellSize * col_number;
  var height = cellSize * row_number;

  // ==========================================================
  var service_group_base = "https://ermon2.cesnet.cz/monitoring/list/servicegroups#!/monitoring/list/services?servicegroup_name=";
  var host_base = "https://ermon2.cesnet.cz/monitoring/list/hosts#!/monitoring/host/show?host="
  var service_base = "https://ermon2.cesnet.cz/#!/monitoring/service/show?host="
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
  var t = d3.transition().duration(3000);

  // ==========================================================

  var svg = $scope.svg;

  // ==========================================================

  // ran only once with initial page display
  if($scope.svg_empty) {
    svg = svg.attr("width", width + margin.left + margin.right)
        .attr("height", height + margin.top + margin.bottom)
        .append("g")
        .attr("transform", "translate(" + margin.left + "," + margin.top + ")");

    // ==========================================================

    var rowLabels = svg.append("g")
        .attr("class", " clickable")
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
        .attr("class", " clickable")
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
    // matrix cells

    var map = svg.append("g").attr("class", "map");

        map.selectAll(".cell")
        .data(data)
        .enter()
        .append("rect")
        .attr("x", function(d) { return (hccol.indexOf(d.col)) * cellSize + 6; })     // compensate for labels
        .attr("y", function(d) { return (hcrow.indexOf(d.row)) * cellSize + 4; })     // compensate for labels
        .attr("class", " clickable cell")
        .attr("width", cellSize - 1)
        .attr("height", cellSize - 1)
        .style("fill", function(d) { return colors[d.value]; })
        .on('mouseover', $scope.cell_tip.show)
        .on('mouseout', $scope.cell_tip.hide)
        .on("click", function(d, i) { window.open(service_base + $scope.radius_servers[d.row] + "&service=%40" + $scope.realms[d.col]); })
        .on("mousedown", function(d, i) { if(d3.event.button == 1) window.open(service_base + $scope.radius_servers[d.row] + "&service=%40" + $scope.realms[d.col]); });

    // ==========================================================
    // legend
      var ordinal = d3.scaleOrdinal()
        .domain(["status = OK", "status = WARNING", "status = CRITICAL", "status = UNKNOWN", "status = PENDING"])
        .range([ colors[0], colors[1], colors[2], colors[3], colors[99] ]);

      svg.append("g")
        .attr("class", "legendOrdinal")
        .attr("transform", "translate(-250, " + ($scope.radius_servers.length * cellSize + 50) + ")");

      var legend = d3.legendColor()
        .scale(ordinal);

      svg.select(".legendOrdinal")
        .call(legend);

      legend = svg.select(".legendCells")
        .append("g")
        .attr("transform", "translate(0, 95)")
        .attr("class", " special")

        legend.append("rect")
        .attr("width", 15)
        .attr("height", 15)
        .style("fill", function(d) { return colors[0]; })

        legend.append("rect")
        .attr("width", cellSize / 4 + 2)
        .attr("height", cellSize / 4 + 2)
        .style("fill", function(d) { return colors[2]; });

        legend.append("text")
        .attr("transform", "translate(25, 12.5)")
        .text("hard status = OK, soft status = CRITICAL");

    // ==========================================================
    // health status
    $scope.svg = svg;
    add_health_status($scope);

    // ==========================================================
    $scope.loading = false;
    $scope.svg_empty = false;
  }

  // ==========================================================
  // update map
  d3.select(".map")
        .selectAll(".cell")       // assign cells data
        .data(data)
        .transition(t)
        .style("fill", function(d, i) { return colors[d.value]; });

  // ==========================================================
  // add soft states
    d3.select(".map")
      .selectAll(".soft")
      //.data(data.filter(function(d) { return d.soft != 0; }))     // TODO - key func
      .data(data.filter(function(d) { return d.soft != 0; }), function(d, i) { return d.row + ":" + d.col; })
      .enter()
      .append("rect")
      .attr("class", " soft")
      .attr("x", function(d) { return (hccol.indexOf(d.col)) * cellSize + 6; })     // compensate for labels
      .attr("y", function(d) { return (hcrow.indexOf(d.row)) * cellSize + 4; })     // compensate for labels
      .attr("width", cellSize / 4 + 2)
      .attr("height", cellSize / 4 + 2)
      .style("fill", function(d) { return colors[d.soft]; });

  // update current soft states
  d3.select(".map")
      .selectAll(".soft")
      .transition(t)
      .style("fill", function(d) { return colors[d.soft]; });

  // delete non existing soft states
  d3.select(".map")
      .selectAll(".soft")
      .exit()
      .remove();

  update_health_status($scope);
}
/* --------------------------------------------------------------------------------- */
// create health status data
/* --------------------------------------------------------------------------------- */
function create_health_status_data($scope)
{
  var keys = Object.keys($scope.total_health);
  var values = Object.values($scope.total_health);
  var health_data = [];

  for(var i in keys)
    health_data.push({key : keys[i], val : values[i]});

  return health_data;
}
/* --------------------------------------------------------------------------------- */
// update health status
/* --------------------------------------------------------------------------------- */
function update_health_status($scope)
{
  var t = d3.transition().duration(3000);
  var health_status = $scope.svg.selectAll('.health_status')
    .selectAll("text")
    .data(create_health_status_data($scope))
    .transition(t)
    .text(function (d) { return d.val; })
}
/* --------------------------------------------------------------------------------- */
// display current overall health status
/* --------------------------------------------------------------------------------- */
function add_health_status($scope)
{
  $scope.svg.append("text")
    .attr("transform", "translate(-250, " + ($scope.radius_servers.length * cellSize + 190) + ")")
    .text("overall health status");

  var health_status = $scope.svg.append("g")
    .attr("transform", "translate(-250, " + ($scope.radius_servers.length * cellSize + 200) + ")")
    .attr("class", "health_status")
    .attr("width", 200)
    .attr("height", 200)
    .selectAll('.legend3')
    .data(create_health_status_data($scope))
    .enter()
    .append('g')

  health_status.append("rect")
    .attr("width", cellSize * 3)
    .attr("height", cellSize)
    .attr("x", function(d, i) { return i * 3 * cellSize; })
    .style("fill", function (d, i) { return colors[d.key]; })

  health_status.append("text")
    .attr("width", cellSize * 3)
    .attr("height", cellSize)
    .attr("x", function(d, i) { return i * 3 * cellSize + cellSize / 2; })
    .attr("y", function(d, i) { return 2 * cellSize; })
    .text(function (d) { return d.val; })
}
/* --------------------------------------------------------------------------------- */
