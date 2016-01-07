
(** Export counters registered with {!Var} as logstash events *)
val get : unit -> [> `Assoc of (string * [>`Floatlit of string | `Int of int | `String of string ]) list ] list

(** Setup periodic saving of counters as logstash json rows along the logfile *)
val setup : Libevent.event_base -> unit
val setup_lwt : unit -> unit
